const crypto = require("node:crypto");
const fsp = require("node:fs/promises");
const path = require("node:path");

const appDirectory = process.env.CRIOMOS_CLAUDE_DESKTOP_TEST_APP;
const declaredClaudeCode = process.env.CLAUDE_CODE_LOCAL_BINARY;
const mode = process.env.CRIOMOS_CLAUDE_DESKTOP_TEST_MODE;
const electron = require("electron");
const hookName = "__CRIOMOS_CLAUDE_CODE_MANAGER";
const sentinel = "CRIOMOS_CLAUDE_CODE_MANAGER_EXPORTED";

console.log("claude-desktop-runtime: bootstrap");

if (!appDirectory || !declaredClaudeCode || !["valid", "missing"].includes(mode)) {
  throw new Error("expected app directory, declared Claude Code executable, and valid or missing mode");
}
if (!process.versions.electron || !electron.app) {
  throw new Error("Claude Desktop runtime contract must execute inside the packaged Electron main process");
}
if (process.env.CLAUDE_CODE_LOCAL_BINARY !== declaredClaudeCode) {
  throw new Error("Claude Desktop did not receive exactly the declared Claude Code executable");
}

function braceEnd(source, start) {
  const bodyStart = source.indexOf("{", start);
  if (bodyStart < 0) throw new Error("Claude Code manager class has no body");
  let depth = 0;
  let quote = null;
  let escaped = false;
  for (let index = bodyStart; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === "'" || character === '"' || character === "`") {
      quote = character;
      continue;
    }
    if (character === "{") depth += 1;
    if (character === "}" && --depth === 0) return index + 1;
  }
  throw new Error("Claude Code manager class is unterminated");
}

async function collectJavaScript(directory, files = []) {
  for (const entry of await fsp.readdir(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) await collectJavaScript(entryPath, files);
    else if (entry.isFile() && entry.name.endsWith(".js")) files.push(entryPath);
  }
  return files;
}

async function exposeActualManager() {
  const files = await collectJavaScript(appDirectory);
  const matches = [];
  for (const file of files) {
    const source = await fsp.readFile(file, "utf8");
    const methodIndex = source.indexOf("async initLocalBinary(e){");
    if (methodIndex >= 0) matches.push({ file, source, methodIndex });
  }
  if (matches.length !== 1) throw new Error(`expected one current Claude Code manager chunk, found ${matches.length}`);
  const { file, source, methodIndex } = matches[0];
  const classStart = source.lastIndexOf("=class{constructor", methodIndex);
  if (classStart < 0) throw new Error("could not locate the actual Claude Code manager class binding");
  const bindingStart = source.lastIndexOf(",", classStart) + 1;
  const binding = source.slice(bindingStart, source.indexOf("=class", bindingStart));
  if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(binding)) {
    throw new Error(`unexpected Claude Code manager binding: ${binding}`);
  }
  const classEnd = braceEnd(source, classStart);
  const classSource = source.slice(classStart, classEnd);
  for (const marker of [
    "this.localBinaryInitPromise=this.initLocalBinary(process.env.CLAUDE_CODE_LOCAL_BINARY)",
    "declared binary unavailable",
    "async invalidateHostBinary(e){if(process.env.CLAUDE_CODE_LOCAL_BINARY)return;",
    "async prepareForVM(e){if(process.env.CLAUDE_CODE_LOCAL_BINARY)throw Error(`CCD local override cannot be materialized for a VM`);",
  ]) {
    if (!classSource.includes(marker)) throw new Error(`Claude Desktop runtime drifted or retained fallback: ${marker}`);
  }
  const hook = `;if(process.env.CRIOMOS_CLAUDE_CODE_MANAGER_HOOK===\"1\"){globalThis.${hookName}=${binding};throw Error(\"${sentinel}\")}`;
  await fsp.writeFile(file, source.slice(0, classEnd) + hook + source.slice(classEnd));
  return file;
}

async function snapshot(directory) {
  const entries = [];
  async function visit(relative) {
    const absolute = path.join(directory, relative);
    const stat = await fsp.lstat(absolute);
    if (stat.isDirectory()) {
      entries.push(`d ${relative}`);
      for (const child of await fsp.readdir(absolute)) await visit(path.join(relative, child));
    } else if (stat.isSymbolicLink()) {
      entries.push(`l ${relative} ${await fsp.readlink(absolute)}`);
    } else if (stat.isFile()) {
      entries.push(`f ${relative} ${stat.mode.toString(8)} ${crypto.createHash("sha256").update(await fsp.readFile(absolute)).digest("hex")}`);
    } else {
      entries.push(`o ${relative}`);
    }
  }
  await visit(".");
  return entries.sort().join("\n");
}

async function assertRejects(action, description) {
  try {
    await action();
  } catch {
    return;
  }
  throw new Error(`${description} unexpectedly completed`);
}

async function main() {
  const roots = [process.env.HOME, process.env.XDG_CONFIG_HOME, process.env.XDG_DATA_HOME, process.env.XDG_CACHE_HOME];
  if (roots.some((root) => !root)) throw new Error("runtime contract requires isolated HOME and XDG roots");
  for (const root of roots) await fsp.mkdir(root, { recursive: true });
  const before = await Promise.all(roots.map(snapshot));

  const chunk = await exposeActualManager();
  process.env.CRIOMOS_CLAUDE_CODE_MANAGER_HOOK = "1";
  try {
    require(chunk);
    throw new Error("Claude Code manager hook did not stop normal application bootstrap");
  } catch (error) {
    if (error?.message !== sentinel) throw error;
  }
  const Manager = globalThis[hookName];
  if (typeof Manager !== "function") throw new Error("actual Claude Code manager was not exported");
  console.log("claude-desktop-runtime: actual manager loaded");
  const manager = new Manager();
  const forbidden = [
    "prepareForTarget",
    "downloadBinaryForTarget",
    "downloadAndVerifyZst",
    "downloadBundleForTarget",
    "cleanupOldVersionsForTarget",
    "maybePrewarmGatekeeper",
    "persistAutoUpdateHighWaterMark",
  ];
  for (const name of forbidden) {
    if (typeof manager[name] !== "function") throw new Error(`runtime drift: missing ${name}`);
    manager[name] = async () => { throw new Error(`stateful Claude Code fallback invoked: ${name}`); };
  }

  if (mode === "valid") {
    console.log("claude-desktop-runtime: valid override");
    if (await manager.getLocalBinaryPath() !== declaredClaudeCode) throw new Error("local override did not resolve the exact declared executable");
    const resolution = await manager.resolveHostBinary();
    if (resolution.path !== declaredClaudeCode || resolution.resolution !== "local_override") {
      throw new Error("host binary resolution was not the exact local override");
    }
    if (await manager.getHostBinaryResolutionKind() !== "local_override") throw new Error("host resolution kind was not local_override");
    if (await manager.getBinaryPathIfReady() !== declaredClaudeCode) throw new Error("ready binary path was not the declared executable");
    const prepared = await manager.prepare();
    if (!prepared.ready || prepared.path !== declaredClaudeCode) throw new Error("prepare did not retain the declared executable");
    const updated = await manager.installUpdatedHostTarget(manager.buildPinVersion, manager.buildPinManifest);
    if (updated.ready || updated.error !== "local override active") throw new Error("auto-update did not stop for local override");
    await manager.invalidateHostBinary();
    await assertRejects(() => manager.prepareForVM(), "VM preparation with a declared local executable");
  } else {
    console.log("claude-desktop-runtime: missing override");
    await assertRejects(() => manager.getLocalBinaryPath(), "missing declared executable initialization");
    await assertRejects(() => manager.resolveHostBinary(), "missing declared executable host resolution");
    await assertRejects(() => manager.prepare(), "missing declared executable preparation");
    await assertRejects(() => manager.getStatus(), "missing declared executable status lookup");
    await assertRejects(() => manager.installUpdatedHostTarget(manager.buildPinVersion, manager.buildPinManifest), "missing declared executable auto-update");
    await manager.invalidateHostBinary();
    await assertRejects(() => manager.prepareForVM(), "missing declared executable VM preparation");
  }

  const after = await Promise.all(roots.map(snapshot));
  if (before.some((value, index) => value !== after[index])) {
    throw new Error("Claude Desktop mutated HOME or XDG state while resolving the declared executable");
  }
}

electron.app.whenReady().then(() => {
  console.log("claude-desktop-runtime: app ready");
  return main();
}).then(
  () => {
    electron.app.quit();
    process.exit(0);
  },
  (error) => {
    console.error(error?.stack || error);
    electron.app.quit();
    process.exit(1);
  },
);
