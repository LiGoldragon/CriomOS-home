import { readFile, readdir, writeFile } from "node:fs/promises";
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

let binaryPatched = false;
for (const file of files) {
  const source = await readFile(file, "utf8");
  const result = replaceOne(
    source,
    "async initLocalBinary(e){",
    "async initLocalBinary(e){try{await y.default.access(e,u.constants.X_OK),this.localBinaryPath=e,F.warn(`[CCD] LOCAL OVERRIDE: Using local binary at ${e}`)}catch{throw Error(`[CCD] LOCAL OVERRIDE: declared binary unavailable at ${e}`)}}",
  );
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
