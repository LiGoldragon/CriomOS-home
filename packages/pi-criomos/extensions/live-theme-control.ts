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

type SocketDataListener = (chunk: string | Buffer) => void;
type SocketCloseListener = () => void;
type SocketErrorListener = (error: Error) => void;

type ActiveContextResult<T> =
  | { state: "inactive" }
  | { state: "failed" }
  | { state: "succeeded"; value: T };

interface LiveThemeControlClientListeners {
  data: SocketDataListener;
  close: SocketCloseListener;
  error: SocketErrorListener;
}

class LiveThemeControlSession {
  private readonly configuration: LiveThemeControlConfiguration;
  private readonly registration: LiveThemeControlRegistration;
  private readonly ctx: ExtensionContext;
  private readonly isCurrentSession: () => boolean;
  private readonly clients: Map<Socket, LiveThemeControlClientListeners> = new Map();
  private active = true;
  private ownsRegistryEntry = false;
  private ownsSocket = false;
  private server: Server | undefined;
  private serverConnectionListener: ((socket: Socket) => void) | undefined;
  private serverRuntimeErrorListener: ((error: Error) => void) | undefined;

  constructor(configuration: LiveThemeControlConfiguration, ctx: ExtensionContext, isCurrentSession: () => boolean) {
    this.configuration = configuration;
    this.registration = configuration.registration();
    this.ctx = ctx;
    this.isCurrentSession = isCurrentSession;
  }

  async start(): Promise<void> {
    await this.registration.prepareDirectory();
    if (!this.isActive()) {
      await this.retireStartedState();
      return;
    }

    const server = createServer();
    const connectionListener = (socket: Socket) =>
      this.containExternalCallback(socket, "accept", () => this.accept(socket));
    server.on("connection", connectionListener);
    this.server = server;
    this.serverConnectionListener = connectionListener;
    await this.listen(server);
    if (!this.isActive()) {
      await this.retireStartedState(server);
      return;
    }

    const runtimeErrorListener = (error: Error) => this.logContainedError("server error", error);
    server.on("error", runtimeErrorListener);
    this.serverRuntimeErrorListener = runtimeErrorListener;
    await this.registration.register();
    this.ownsRegistryEntry = true;
    if (!this.isActive()) {
      await this.retireStartedState(server);
      return;
    }

    this.setStatus(undefined);
  }

  async shutdown(): Promise<void> {
    await this.retireStartedState();
  }

  notifySocketUnavailable(error: unknown): void {
    this.notify(`Live theme control socket unavailable: ${String(error)}`, "warning");
  }

  private isActive(): boolean {
    return this.active && this.isCurrentSession();
  }

  private async retireStartedState(startingServer?: Server): Promise<void> {
    this.active = false;
    for (const client of Array.from(this.clients.keys())) {
      this.destroyClient(client);
    }
    const server = startingServer ?? this.server;
    if (this.server === server) {
      this.server = undefined;
    }
    if (server) {
      this.detachServerListeners(server);
      if (server.listening) {
        await new Promise<void>((resolve) => server.close(() => resolve()));
      }
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
        try {
          server.off("listening", succeed);
        } catch (cleanupError) {
          this.logContainedError("listen failure cleanup", cleanupError);
        }
        reject(error);
      };
      const succeed = () => {
        try {
          server.off("error", fail);
          this.ownsSocket = true;
          resolve();
        } catch (error) {
          reject(error);
        }
      };
      server.once("error", fail);
      server.once("listening", succeed);
      server.listen(this.registration.socketPath);
    });
  }

  private accept(socket: Socket): void {
    if (!this.isActive()) {
      this.destroySocket(socket);
      return;
    }
    let buffer = "";
    const listeners: LiveThemeControlClientListeners = {
      data: (chunk) => {
        this.containExternalCallback(socket, "data", () => {
          if (!this.isActive()) {
            this.destroyClient(socket);
            return;
          }
          buffer += chunk;
          buffer = this.consumeLines(buffer);
        });
      },
      close: () => this.containExternalCallback(socket, "close", () => this.detachClient(socket)),
      error: () => this.containExternalCallback(socket, "error", () => this.detachClient(socket)),
    };
    this.clients.set(socket, listeners);
    socket.setEncoding("utf8");
    socket.on("data", listeners.data);
    socket.on("close", listeners.close);
    socket.on("error", listeners.error);
  }

  private consumeLines(buffer: string): string {
    let remainder = buffer;
    let newlineIndex = remainder.indexOf("\n");
    while (newlineIndex >= 0) {
      const line = remainder.slice(0, newlineIndex);
      remainder = remainder.slice(newlineIndex + 1);
      if (!this.isActive()) {
        return remainder;
      }
      this.applyLine(line);
      newlineIndex = remainder.indexOf("\n");
    }
    return remainder;
  }

  private applyLine(line: string): void {
    if (!this.isActive()) {
      return;
    }
    const selection = this.configuration.selectionFor(line);
    if (!selection) {
      this.notify(`Live theme control ignored unknown mode: ${line}`, "warning");
      return;
    }
    const result = this.useActiveContext("set theme", (ctx) => {
      const themeInstance = ctx.ui.getTheme(selection.themeName);
      if (!themeInstance) {
        return { success: false, error: `theme not found: ${selection.themeName}` };
      }
      return ctx.ui.setTheme(themeInstance);
    });
    if (result.state !== "succeeded" || !this.isActive()) {
      return;
    }
    const themeResult = result.value;
    if (themeResult.success) {
      this.setStatus(`${selection.mode}: ${selection.themeName}`);
    } else {
      const errorMessage = "error" in themeResult ? themeResult.error : "unknown error";
      this.notify(`Live theme control failed to set ${selection.themeName}: ${errorMessage}`, "error");
    }
  }

  private setStatus(status: string | undefined): void {
    this.useActiveContext("set status", (ctx) => {
      ctx.ui.setStatus(this.configuration.statusName, status);
    });
  }

  private notify(message: string, level: "info" | "warning" | "error"): void {
    this.useActiveContext("notify", (ctx) => {
      ctx.ui.notify(message, level);
    });
  }

  private useActiveContext<T>(operationName: string, operation: (ctx: ExtensionContext) => T): ActiveContextResult<T> {
    if (!this.isActive()) {
      return { state: "inactive" };
    }
    try {
      return { state: "succeeded", value: operation(this.ctx) };
    } catch (error) {
      this.logContainedError(`ui ${operationName}`, error);
      return { state: "failed" };
    }
  }

  private containExternalCallback(socket: Socket, operationName: string, operation: () => void): void {
    try {
      operation();
    } catch (error) {
      this.destroyClientAfterContainedFailure(socket, operationName);
      this.logContainedError(`socket ${operationName}`, error);
    }
  }

  private destroyClientAfterContainedFailure(socket: Socket, operationName: string): void {
    try {
      this.destroyClient(socket);
    } catch (cleanupError) {
      this.logContainedError(`socket ${operationName} cleanup`, cleanupError);
    }
  }

  private destroyClient(socket: Socket): void {
    this.detachClient(socket);
    this.destroySocket(socket);
  }

  private destroySocket(socket: Socket): void {
    const ignoreDestroyError = () => undefined;
    socket.on("error", ignoreDestroyError);
    socket.once("close", () => {
      try {
        socket.off("error", ignoreDestroyError);
      } catch (error) {
        this.logContainedError("socket destroy cleanup", error);
      }
    });
    socket.destroy();
  }

  private detachClient(socket: Socket): void {
    const listeners = this.clients.get(socket);
    if (!listeners) {
      return;
    }
    socket.off("data", listeners.data);
    socket.off("close", listeners.close);
    socket.off("error", listeners.error);
    this.clients.delete(socket);
  }

  private detachServerListeners(server: Server): void {
    if (this.serverConnectionListener) {
      server.off("connection", this.serverConnectionListener);
      this.serverConnectionListener = undefined;
    }
    if (this.serverRuntimeErrorListener) {
      server.off("error", this.serverRuntimeErrorListener);
      this.serverRuntimeErrorListener = undefined;
    }
  }

  private logContainedError(operationName: string, error: unknown): void {
    try {
      console.error(`live-theme-control contained ${operationName} error: ${String(error)}`);
    } catch {
      // Intentionally empty: logging must not turn a contained socket callback failure into a process crash.
    }
  }
}

export default function (pi: ExtensionAPI) {
  const configuration = LiveThemeControlConfiguration.fromEnvironment();
  let session: LiveThemeControlSession | undefined;
  let sessionGeneration = 0;

  pi.on("session_start", async (_event, ctx) => {
    sessionGeneration += 1;
    const previousSession = session;
    session = undefined;
    await previousSession?.shutdown();

    const currentGeneration = sessionGeneration;
    let nextSession: LiveThemeControlSession;
    nextSession = new LiveThemeControlSession(
      configuration,
      ctx,
      () => session === nextSession && sessionGeneration === currentGeneration,
    );
    session = nextSession;
    try {
      await nextSession.start();
    } catch (error) {
      if (session === nextSession) {
        nextSession.notifySocketUnavailable(error);
        session = undefined;
        sessionGeneration += 1;
      }
      await nextSession.shutdown().catch(() => undefined);
    }
  });

  pi.on("session_shutdown", async () => {
    sessionGeneration += 1;
    const currentSession = session;
    session = undefined;
    await currentSession?.shutdown();
  });
}
