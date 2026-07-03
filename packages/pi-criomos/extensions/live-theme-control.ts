import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { mkdir, unlink } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { dirname, join } from "node:path";

type ThemeMode = "dark" | "light";

interface ThemeSelection {
  mode: ThemeMode;
  themeName: string;
}

class LiveThemeControlConfiguration {
  readonly statusName: string;
  readonly socketPath: string;
  readonly darkThemeName: string;
  readonly lightThemeName: string;

  private constructor(input: {
    statusName: string;
    socketPath: string;
    darkThemeName: string;
    lightThemeName: string;
  }) {
    this.statusName = input.statusName;
    this.socketPath = input.socketPath;
    this.darkThemeName = input.darkThemeName;
    this.lightThemeName = input.lightThemeName;
  }

  static fromEnvironment(): LiveThemeControlConfiguration {
    return new LiveThemeControlConfiguration({
      statusName: process.env.PI_LIVE_THEME_CONTROL_STATUS ?? "live-theme-control",
      socketPath: process.env.PI_LIVE_THEME_CONTROL_SOCKET ?? LiveThemeControlConfiguration.defaultSocketPath(),
      darkThemeName: process.env.PI_LIVE_THEME_CONTROL_DARK_THEME ?? "criomos-dark",
      lightThemeName: process.env.PI_LIVE_THEME_CONTROL_LIGHT_THEME ?? "criomos-light",
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

  private static defaultSocketPath(): string {
    const runtimeDirectory = process.env.XDG_RUNTIME_DIR;
    if (runtimeDirectory && runtimeDirectory.length > 0) {
      return join(runtimeDirectory, "chroma", "pi-live-theme.sock");
    }
    return join(process.env.HOME ?? "/tmp", ".cache", "pi-live-theme.sock");
  }
}

class LiveThemeControlSession {
  private readonly configuration: LiveThemeControlConfiguration;
  private readonly ctx: ExtensionContext;
  private readonly clients: Set<Socket> = new Set();
  private active = true;
  private ownsSocket = false;
  private server: Server | undefined;

  constructor(configuration: LiveThemeControlConfiguration, ctx: ExtensionContext) {
    this.configuration = configuration;
    this.ctx = ctx;
  }

  async start(): Promise<void> {
    await mkdir(dirname(this.configuration.socketPath), { recursive: true });
    const server = createServer((socket) => this.accept(socket));
    this.server = server;
    await this.listen(server);
    if (this.active) {
      this.ctx.ui.setStatus(this.configuration.statusName, "theme socket listening");
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
    if (this.ownsSocket) {
      this.ownsSocket = false;
      await unlink(this.configuration.socketPath).catch(() => undefined);
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
      server.listen(this.configuration.socketPath);
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
      session = undefined;
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
