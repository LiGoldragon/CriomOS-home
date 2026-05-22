import * as childProcess from "node:child_process";
import * as filesystem from "node:fs";
import * as operatingSystem from "node:os";
import * as path from "node:path";
import {
	isToolCallEventType,
	type ExtensionAPI,
	type ExtensionContext,
	type ToolCallEventResult,
	type UserBashEventResult,
} from "@earendil-works/pi-coding-agent";

const protectedPaths = [
	"~/primary/intent",
	"~/.local/state/persona-spirit",
	"~/WT",
	"~/wt",
	"/git/github.com/LiGoldragon/CriomOS-home/flake.lock",
	"/git/github.com/LiGoldragon/CriomOS/flake.lock",
	"/git/github.com/LiGoldragon/lojix-cli/flake.lock",
];

const destructiveCommandPatterns = [
	/\brm\s+(?:-[A-Za-z]*[rR][A-Za-z]*[fF]|-[A-Za-z]*[fF][A-Za-z]*[rR]|--recursive|--force)/,
	/\bjj\s+abandon\b/,
	/\bjj\s+restore\b/,
	/\bjj\s+git\s+push\b.*\B--force\b/,
	/\bgit\s+reset\s+--hard\b/,
	/\bgit\s+clean\s+-[^\n]*[fdx]/,
	/\bgit\s+push\b.*\B--force\b/,
	/\bsudo\b|\brun0\b/,
	/\bswitch-to-configuration\s+switch\b/,
];

function expandUserHome(candidatePath: string): string {
	if (candidatePath === "~") return operatingSystem.homedir();
	if (candidatePath.startsWith("~/")) return path.join(operatingSystem.homedir(), candidatePath.slice(2));
	return candidatePath;
}

function absolutePath(candidatePath: string, workingDirectory: string): string {
	const expandedPath = expandUserHome(candidatePath);
	return path.resolve(workingDirectory, expandedPath);
}

function isInside(candidatePath: string, directoryPath: string): boolean {
	const relativePath = path.relative(directoryPath, candidatePath);
	return relativePath === "" || (!relativePath.startsWith("..") && !path.isAbsolute(relativePath));
}

function matchedProtectedPath(candidatePath: string, workingDirectory: string): string | undefined {
	const resolvedCandidate = absolutePath(candidatePath, workingDirectory);
	for (const configuredPath of protectedPaths) {
		const resolvedProtectedPath = absolutePath(configuredPath, operatingSystem.homedir());
		if (isInside(resolvedCandidate, resolvedProtectedPath)) return configuredPath;
	}
	return undefined;
}

function commandLooksDestructive(command: string): boolean {
	return destructiveCommandPatterns.some((pattern) => pattern.test(command));
}

function findJujutsuRoot(workingDirectory: string): string | undefined {
	try {
		const output = childProcess.execFileSync("jj", ["root"], {
			cwd: workingDirectory,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		});
		return output.trim() || undefined;
	} catch {
		return undefined;
	}
}

function repositoryIsDirty(repositoryRoot: string): boolean {
	try {
		const output = childProcess.execFileSync("jj", ["--no-pager", "status"], {
			cwd: repositoryRoot,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		});
		return output.trim() !== "" && !output.includes("The working copy is clean");
	} catch {
		return false;
	}
}

async function confirmOrBlock(
	context: ExtensionContext,
	title: string,
	message: string,
): Promise<ToolCallEventResult | undefined> {
	if (!context.hasUI) {
		return { block: true, reason: `${title}: interactive confirmation unavailable` };
	}
	const allowed = await context.ui.confirm(title, message);
	if (!allowed) return { block: true, reason: title };
	return undefined;
}

async function confirmShellCommand(
	command: string,
	context: ExtensionContext,
): Promise<ToolCallEventResult | undefined> {
	if (!commandLooksDestructive(command)) return undefined;
	return confirmOrBlock(context, "CriomOS operator safety", `Allow potentially destructive command?\n\n${command}`);
}

async function confirmProtectedMutation(
	targetPath: string,
	context: ExtensionContext,
): Promise<ToolCallEventResult | undefined> {
	const protectedPath = matchedProtectedPath(targetPath, context.cwd);
	if (!protectedPath) return undefined;
	return confirmOrBlock(
		context,
		"CriomOS protected path",
		`Allow mutation under protected path ${protectedPath}?\n\n${targetPath}`,
	);
}

async function confirmDirtyRepositoryMutation(
	targetPath: string,
	context: ExtensionContext,
): Promise<ToolCallEventResult | undefined> {
	const resolvedTargetPath = absolutePath(targetPath, context.cwd);
	const directoryPath = filesystem.existsSync(resolvedTargetPath) && filesystem.statSync(resolvedTargetPath).isDirectory()
		? resolvedTargetPath
		: path.dirname(resolvedTargetPath);
	const repositoryRoot = findJujutsuRoot(directoryPath);
	if (!repositoryRoot || !repositoryIsDirty(repositoryRoot)) return undefined;
	return confirmOrBlock(
		context,
		"CriomOS dirty repository",
		`Repository already has working-copy changes. Allow mutation?\n\n${repositoryRoot}\n${targetPath}`,
	);
}

function blockedUserBashResult(reason: string): UserBashEventResult {
	return {
		result: {
			output: `${reason}\n`,
			exitCode: 1,
			cancelled: false,
			truncated: false,
		},
	};
}

export default function registerCriomOSOperatorSafety(pi: ExtensionAPI): void {
	pi.on("before_agent_start", async (event) => {
		return {
			systemPrompt: `${event.systemPrompt}

CriomOS operator safety:
- Use subagents only when the psyche explicitly asks for delegation or parallel agent work.
- Treat intent records, Spirit state, deployment lock files, and production flake locks as protected surfaces.
- Prefer jj and workspace orchestration rules before raw git or direct file surgery.`,
		};
	});

	pi.on("tool_call", async (event, context) => {
		if (isToolCallEventType("bash", event)) {
			return confirmShellCommand(event.input.command, context);
		}

		if (isToolCallEventType("write", event) || isToolCallEventType("edit", event)) {
			const targetPath = event.input.path;
			return (
				(await confirmProtectedMutation(targetPath, context)) ??
				(await confirmDirtyRepositoryMutation(targetPath, context))
			);
		}

		return undefined;
	});

	pi.on("user_bash", async (event, context) => {
		const confirmation = await confirmShellCommand(event.command, context);
		if (!confirmation?.block) return undefined;
		return blockedUserBashResult(confirmation.reason ?? "blocked by CriomOS operator safety");
	});
}
