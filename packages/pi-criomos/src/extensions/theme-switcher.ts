import * as filesystem from "node:fs";
import * as operatingSystem from "node:os";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type ChromaMode = "dark" | "light";

const statusKey = "criomos-theme";
const stateDirectory = process.env.XDG_STATE_HOME ?? path.join(operatingSystem.homedir(), ".local", "state");
const modePath = path.join(stateDirectory, "chroma", "current-mode");

let watcher: filesystem.FSWatcher | undefined;
let interval: NodeJS.Timeout | undefined;
let appliedTheme: string | undefined;

function readMode(): ChromaMode | undefined {
	try {
		const value = filesystem.readFileSync(modePath, "utf8").trim().toLowerCase();
		if (value === "dark" || value === "light") return value;
	} catch {
		return undefined;
	}
	return undefined;
}

function themeName(mode: ChromaMode): string {
	return `criomos-${mode}`;
}

function applyChromaTheme(context: ExtensionContext): void {
	if (!context.hasUI) return;
	const mode = readMode();
	if (!mode) {
		context.ui.setStatus(statusKey, "theme: chroma state missing");
		return;
	}
	const nextTheme = themeName(mode);
	if (appliedTheme === nextTheme && context.ui.theme.name === nextTheme) return;

	const result = context.ui.setTheme(nextTheme);
	if (result.success) {
		appliedTheme = nextTheme;
		context.ui.setStatus(statusKey, `theme: ${mode}`);
		return;
	}

	context.ui.setStatus(statusKey, `theme: ${result.error ?? "switch failed"}`);
}

function stopWatcher(): void {
	watcher?.close();
	watcher = undefined;
	if (interval) {
		clearInterval(interval);
		interval = undefined;
	}
}

function startWatcher(context: ExtensionContext): void {
	stopWatcher();
	applyChromaTheme(context);

	const chromaDirectory = path.dirname(modePath);
	try {
		watcher = filesystem.watch(chromaDirectory, { persistent: false }, (_event, fileName) => {
			if (fileName !== "current-mode") return;
			setTimeout(() => applyChromaTheme(context), 50);
		});
	} catch {
		context.ui.setStatus(statusKey, "theme: chroma watch unavailable");
	}

	interval = setInterval(() => applyChromaTheme(context), 30000);
	interval.unref?.();
}

export default function registerCriomOSThemeSwitcher(pi: ExtensionAPI): void {
	pi.on("session_start", async (_event, context) => {
		startWatcher(context);
	});

	pi.on("before_provider_request", async (_event, context) => {
		applyChromaTheme(context);
	});

	pi.on("tool_call", async (_event, context) => {
		applyChromaTheme(context);
	});

	pi.on("session_shutdown", async () => {
		stopWatcher();
	});
}
