import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { randomUUID } from "node:crypto";
import { mkdir, unlink, writeFile } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { basename, join } from "node:path";

const registryEntryExtension = ".path";
const socketExtension = ".sock";

type ThemeMode = "dark" | "light";

interface ThemeSelection {
  mode: ThemeMode;
  themeName: string;
}

class LiveThemeControlConfiguration {
  readonly statusName: string;
  readonly registryDirectory: string;
  readonly darkThemeName: string;
  readonly lightThemeName: string;

  private constructor(input: {
    statusName: string;
    registryDirectory: string;
    darkThemeName: string;
    lightThemeName: string;
  }) {
    this.statusName = input.statusName;
    this.registryDirectory = input.registryDirectory;
    this.darkThemeName = input.darkThemeName;
    this.lightThemeName = input.lightThemeName;
  }

  static fromEnvironment(): LiveThemeControlConfiguration {
    return new LiveThemeControlConfiguration({
      statusName: process.env.PI_LIVE_THEME_CONTROL_STATUS ?? "live-theme-control",
      registryDirectory:
        process.env.PI_LIVE_THEME_CONTROL_REGISTRY_DIRECTORY ??
        LiveThemeControlConfiguration.defaultRegistryDirectory(),
      darkThemeName: process.env.PI_LIVE_THEME_CONTROL_DARK_THEME ?? "criomos-dark",
      lightThemeName: process.env.PI_LIVE_THEME_CONTROL_LIGHT_THEME ?? "criomos-light",
    });
  }

  registration(): LiveThemeControlRegistration {
    const stem = `pi-${process.pid}-${Date.now()}-${randomUUID()}`;
    return new LiveThemeControlRegistration({
      registryDirectory: this.registryDirectory,
      socketPath: join(this.registryDirectory, `${stem}${socketExtension}`),
      registryEntryPath: join(this.registryDirectory, `${stem}${registryEntryExtension}`),
    });
  }

  selectionFor(line: string): ThemeSelection | undefined {
    const mode = line.trim().toLowerCase();
    if (mode === "dark") {
      return { mode, themeName: this.darkThemeName };
    }
    if (mode === "light") {
      return { mode, themeName: this.lightThemeName };
    }
    return undefined;
  }

  private static defaultRegistryDirectory(): string {
    const runtimeDirectory = process.env.XDG_RUNTIME_DIR;
    if (runtimeDirectory && runtimeDirectory.length > 0) {
      return join(runtimeDirectory, "chroma", "pi-live-theme.d");
    }
    return join(process.env.HOME ?? "/tmp", ".cache", "pi-live-theme.d");
  }
}

class LiveThemeControlRegistration {
  readonly registryDirectory: string;
  readonly socketPath: string;
  readonly registryEntryPath: string;

  constructor(input: { registryDirectory: string; socketPath: string; registryEntryPath: string }) {
    this.registryDirectory = input.registryDirectory;
    this.socketPath = input.socketPath;
    this.registryEntryPath = input.registryEntryPath;
  }

  async prepareDirectory(): Promise<void> {
    await mkdir(this.registryDirectory, { recursive: true });
  }

  async register(): Promise<void> {
    await writeFile(this.registryEntryPath, `${this.socketPath}\n`, { mode: 0o600 });
  }

  async unregister(): Promise<void> {
    await unlink(this.registryEntryPath).catch(() => undefined);
  }

  async removeSocket(): Promise<void> {
    await unlink(this.socketPath).catch(() => undefined);
  }

  displayName(): string {
    return basename(this.socketPath);
  }
}

class LiveThemeControlSession {
  private readonly configuration: LiveThemeControlConfiguration;
  private readonly registration: LiveThemeControlRegistration;
  private readonly ctx: ExtensionContext;
  private readonly clients: Set<Socket> = new Set();
  private active = true;
  private ownsRegistryEntry = false;
  private ownsSocket = false;
  private server: Server | undefined;

  constructor(configuration: LiveThemeControlConfiguration, ctx: ExtensionContext) {
    this.configuration = configuration;
    this.registration = configuration.registration();
    this.ctx = ctx;
  }

  async start(): Promise<void> {
    await this.registration.prepareDirectory();
    const server = createServer((socket) => this.accept(socket));
    this.server = server;
    await this.listen(server);
    await this.registration.register();
    this.ownsRegistryEntry = true;
    if (this.active) {
      this.ctx.ui.setStatus(
        this.configuration.statusName,
        `theme socket registered: ${this.registration.displayName()}`,
      );
    }
  }

  async shutdown(): Promise<void> {
    if (!this.active) {
      return;
    }
    this.active = false;
    for (const client of this.clients) {
      client.destroy();
    }
    this.clients.clear();
    const server = this.server;
    this.server = undefined;
    if (server?.listening) {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
    if (this.ownsRegistryEntry) {
      this.ownsRegistryEntry = false;
      await this.registration.unregister();
    }
    if (this.ownsSocket) {
      this.ownsSocket = false;
      await this.registration.removeSocket();
    }
  }

  private listen(server: Server): Promise<void> {
    return new Promise((resolve, reject) => {
      const fail = (error: Error) => {
        server.off("listening", succeed);
        reject(error);
      };
      const succeed = () => {
        server.off("error", fail);
        this.ownsSocket = true;
        resolve();
      };
      server.once("error", fail);
      server.once("listening", succeed);
      server.listen(this.registration.socketPath);
    });
  }

  private accept(socket: Socket): void {
    if (!this.active) {
      socket.destroy();
      return;
    }
    this.clients.add(socket);
    socket.setEncoding("utf8");
    let buffer = "";
    socket.on("data", (chunk) => {
      if (!this.active) {
        socket.destroy();
        return;
      }
      buffer += chunk;
      buffer = this.consumeLines(buffer);
    });
    socket.on("close", () => this.clients.delete(socket));
    socket.on("error", () => this.clients.delete(socket));
  }

  private consumeLines(buffer: string): string {
    let remainder = buffer;
    let newlineIndex = remainder.indexOf("\n");
    while (newlineIndex >= 0) {
      const line = remainder.slice(0, newlineIndex);
      remainder = remainder.slice(newlineIndex + 1);
      this.applyLine(line);
      newlineIndex = remainder.indexOf("\n");
    }
    return remainder;
  }

  private applyLine(line: string): void {
    if (!this.active) {
      return;
    }
    const selection = this.configuration.selectionFor(line);
    if (!selection) {
      this.ctx.ui.notify(`Live theme control ignored unknown mode: ${line}`, "warning");
      return;
    }
    const result = this.ctx.ui.setTheme(selection.themeName);
    if (!this.active) {
      return;
    }
    if (result.success) {
      this.ctx.ui.setStatus(this.configuration.statusName, `${selection.mode}: ${selection.themeName}`);
    } else {
      this.ctx.ui.notify(`Live theme control failed to set ${selection.themeName}: ${result.error}`, "error");
    }
  }
}

export default function (pi: ExtensionAPI) {
  const configuration = LiveThemeControlConfiguration.fromEnvironment();
  let session: LiveThemeControlSession | undefined;

  pi.on("session_start", async (_event, ctx) => {
    await session?.shutdown();
    const nextSession = new LiveThemeControlSession(configuration, ctx);
    session = nextSession;
    try {
      await nextSession.start();
    } catch (error) {
      if (session === nextSession) {
        session = undefined;
      }
      await nextSession.shutdown().catch(() => undefined);
      ctx.ui.notify(`Live theme control socket unavailable: ${String(error)}`, "warning");
    }
  });

  pi.on("session_shutdown", async () => {
    const currentSession = session;
    session = undefined;
    await currentSession?.shutdown();
  });
}
