import { readFile, readdir, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join } from "node:path";

const [appDirectory, declaredClaudeCode] = process.argv.slice(2);
if (!appDirectory || !declaredClaudeCode) {
  throw new Error("expected extracted app directory and declared Claude Code executable");
}

const files = [];
async function collect(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) await collect(entryPath);
    else if (entry.isFile() && entry.name.endsWith(".js")) files.push(entryPath);
  }
}

function methodEnd(source, start) {
  const bodyStart = source.indexOf("{", start);
  if (bodyStart < 0) throw new Error("method has no body");
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
    if (character === "}") {
      depth -= 1;
      if (depth === 0) return index + 1;
    }
  }
  throw new Error("unterminated method body");
}

function replaceOne(source, marker, replacement) {
  const start = source.indexOf(marker);
  if (start < 0) return null;
  if (source.indexOf(marker, start + marker.length) >= 0) {
    throw new Error(`ambiguous runtime method: ${marker}`);
  }
  return source.slice(0, start) + replacement + source.slice(methodEnd(source, start));
}

function prefixOne(source, marker, prefix) {
  const start = source.indexOf(marker);
  if (start < 0) return null;
  if (source.indexOf(marker, start + marker.length) >= 0) {
    throw new Error(`ambiguous runtime method: ${marker}`);
  }
  return source.slice(0, start + marker.length) + prefix + source.slice(start + marker.length);
}

await collect(appDirectory);
let constructorPatched = false;
const constructorMarker = "process.env.CLAUDE_CODE_LOCAL_BINARY}";
const constructorReplacement = `this.localBinaryOverridePath=${JSON.stringify(declaredClaudeCode)},this.localBinaryInitPromise=this.initLocalBinary(this.localBinaryOverridePath)}`;
for (const file of files) {
  const source = await readFile(file, "utf8");
  const start = source.indexOf(constructorMarker);
  if (start < 0) continue;
  if (constructorPatched || source.indexOf(constructorMarker, start + constructorMarker.length) >= 0) {
    throw new Error("ambiguous Claude Code local-override constructor");
  }
  await writeFile(file, source.replace(constructorMarker, constructorReplacement));
  constructorPatched = true;
}
if (!constructorPatched) throw new Error("Claude Code local-override constructor was not found");

// The injected method resolves everything it needs itself. It must never read
// a minified identifier from the enclosing bundle scope: those names change
// with every upstream build, and a stale one throws a ReferenceError that the
// old `catch` reported as a missing binary.
const unavailableMessage = (path) => `[CCD] LOCAL OVERRIDE: declared binary unavailable at ${path}`;
const localBinaryMethod = [
  "async initLocalBinary(e){",
  "let executable=!1;",
  "try{",
  'const nodeFs=require("node:fs");',
  "try{nodeFs.accessSync(e,nodeFs.constants.X_OK),executable=!0}catch{executable=!1}",
  "}catch(internal){",
  "throw Error(`[CCD] LOCAL OVERRIDE: internal error resolving declared binary at ${e}: ${internal&&internal.stack||internal}`)",
  "}",
  "if(!executable)throw Error(`[CCD] LOCAL OVERRIDE: declared binary unavailable at ${e}`);",
  "this.localBinaryPath=e;",
  "try{console.warn(`[CCD] LOCAL OVERRIDE: Using local binary at ${e}`)}catch{}",
  "}",
].join("");

// Execute the injected method here, at build time, so a bundle change can only
// ever break the build and never the running application.
const probeRequire = createRequire(import.meta.url);
const probe = (injectedRequire) => new Function("require", `return {${localBinaryMethod}}`)(injectedRequire);

async function expectRejection(method, path, expected, description) {
  const holder = { localBinaryPath: null };
  try {
    await method.call(holder, path);
  } catch (error) {
    if (error?.message !== expected) {
      throw new Error(`${description} reported ${JSON.stringify(error?.message)}, expected ${JSON.stringify(expected)}`);
    }
    return;
  }
  throw new Error(`${description} unexpectedly succeeded`);
}

{
  const absent = join(appDirectory, "criomos-absent-declared-binary");
  await expectRejection(probe(probeRequire).initLocalBinary, absent, unavailableMessage(absent), "absent declared binary");

  const broken = () => {
    throw new TypeError("require is not available");
  };
  const holder = { localBinaryPath: null };
  let internalMessage = null;
  try {
    await probe(broken).initLocalBinary.call(holder, declaredClaudeCode);
  } catch (error) {
    internalMessage = error?.message ?? "";
  }
  if (internalMessage === null) throw new Error("injected override ignored a broken host environment");
  if (internalMessage === unavailableMessage(declaredClaudeCode)) {
    throw new Error("injected override reported an internal failure as a missing binary");
  }
  if (!internalMessage.startsWith("[CCD] LOCAL OVERRIDE: internal error")) {
    throw new Error(`injected override reported an unexpected internal failure: ${internalMessage}`);
  }

  // The declared executable is absent by construction in the fail-closed
  // contract check, so assert whichever outcome the real path warrants.
  let declaredIsExecutable = true;
  try {
    probeRequire("node:fs").accessSync(declaredClaudeCode, probeRequire("node:fs").constants.X_OK);
  } catch {
    declaredIsExecutable = false;
  }
  if (declaredIsExecutable) {
    const resolved = { localBinaryPath: null };
    await probe(probeRequire).initLocalBinary.call(resolved, declaredClaudeCode);
    if (resolved.localBinaryPath !== declaredClaudeCode) {
      throw new Error(`injected override resolved ${JSON.stringify(resolved.localBinaryPath)}, expected ${JSON.stringify(declaredClaudeCode)}`);
    }
  } else {
    await expectRejection(
      probe(probeRequire).initLocalBinary,
      declaredClaudeCode,
      unavailableMessage(declaredClaudeCode),
      "declared binary absent from the store",
    );
  }
}

let binaryPatched = false;
for (const file of files) {
  const source = await readFile(file, "utf8");
  const result = replaceOne(source, "async initLocalBinary(e){", localBinaryMethod);
  if (result === null) continue;
  if (binaryPatched) throw new Error("Claude Code local-binary method occurs more than once");
  await writeFile(file, result);
  binaryPatched = true;
}
if (!binaryPatched) throw new Error("Claude Code local-binary method was not found");

for (const [marker, prefix] of [
  ["async invalidateHostBinary(e){", "if(this.localBinaryOverridePath)return;"],
  ["async prepareForVM(e){", "if(this.localBinaryOverridePath)throw Error(`CCD local override cannot be materialized for a VM`);"],
]) {
  let patched = false;
  for (const file of files) {
    const source = await readFile(file, "utf8");
    const result = prefixOne(source, marker, prefix);
    if (result === null) continue;
    if (patched) throw new Error(`runtime method occurs in more than one file: ${marker}`);
    await writeFile(file, result);
    patched = true;
  }
  if (!patched) throw new Error(`runtime method was not found: ${marker}`);
}
