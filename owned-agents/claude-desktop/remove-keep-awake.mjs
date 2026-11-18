// Remove Claude Desktop's keep-awake power-save blocker from the extracted app.
//
// Chromium before 157.0.8092 suspends the screensaver for the
// "prevent-app-suspension" wake-lock type, which on Wayland is a
// zwp_idle_inhibitor_v1 on the focused window. The remote-tools credential
// rotation starts that blocker every thirty minutes, so the compositor's idle
// timers (screen off, session lock) are cancelled before they can expire.
//
// The call is replaced by an inert id. The app's start and stop bookkeeping
// stays as it is, and stopping an id that was never started does nothing.
import { readFile, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const [appDirectory] = process.argv.slice(2);
if (!appDirectory) throw new Error("expected the extracted app directory");

const files = [];
async function collect(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = join(directory, entry.name);
    if (entry.isDirectory()) await collect(entryPath);
    else if (entry.isFile() && /\.(c|m)?js$/.test(entry.name)) files.push(entryPath);
  }
}

// The electron module's local name is minified and differs between builds.
const keepAwakeCall = /[\w$]+\.powerSaveBlocker\.start\("prevent-app-suspension"\)/g;
const inertId = "-1";

await collect(appDirectory);
let replaced = 0;
for (const file of files) {
  const source = await readFile(file, "utf8");
  const found = source.match(keepAwakeCall)?.length ?? 0;
  if (found === 0) continue;
  await writeFile(file, source.replace(keepAwakeCall, inertId));
  replaced += found;
}
if (replaced !== 1) {
  throw new Error(
    `expected exactly one keep-awake powerSaveBlocker.start call, found ${replaced}; ` +
      "the patch is for Chromium before 157.0.8092 and goes once a release ships that or later",
  );
}
console.log(`claude-desktop: removed the keep-awake power-save blocker from ${replaced} call site`);
