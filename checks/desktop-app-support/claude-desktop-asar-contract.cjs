// A packed `.node` cannot be dlopen'd: the pty host fails to load pty.node and
// every in-app terminal dies. Assert the shipped archive keeps its native
// modules unpacked and that the unpacked files are really on disk.
const fs = require("node:fs");
const path = require("node:path");

const [archive] = process.argv.slice(2);
if (!archive) throw new Error("expected the packaged app.asar path");

const requiredUnpacked = [
  "node_modules/node-pty/prebuilds/linux-x64/pty.node",
  "node_modules/@ant/claude-native/claude-native-binding.node",
];

const image = fs.readFileSync(archive);
if (image.length < 16) throw new Error(`not an asar archive: ${archive}`);
const headerSize = image.readUInt32LE(12);
const header = JSON.parse(image.subarray(16, 16 + headerSize).toString("utf8"));

const unpacked = [];
const packed = [];
(function walk(node, prefix) {
  for (const [name, entry] of Object.entries(node.files ?? {})) {
    const entryPath = prefix ? `${prefix}/${name}` : name;
    if (entry.files) walk(entry, entryPath);
    else if (entry.unpacked) unpacked.push(entryPath);
    else packed.push(entryPath);
  }
})(header, "");

if (unpacked.length === 0) {
  throw new Error(`app.asar header marks nothing unpacked: ${archive}`);
}
const packedNative = packed.filter((entry) => entry.endsWith(".node"));
if (packedNative.length !== 0) {
  throw new Error(`native modules stored inside app.asar: ${packedNative.join(", ")}`);
}
for (const required of requiredUnpacked) {
  if (!unpacked.includes(required)) {
    throw new Error(`app.asar header does not mark ${required} unpacked`);
  }
}
for (const entry of unpacked) {
  const onDisk = path.join(`${archive}.unpacked`, entry);
  const stat = fs.statSync(onDisk);
  if (!stat.isFile() || stat.size === 0) {
    throw new Error(`unpacked entry is not a real file: ${onDisk}`);
  }
}

console.log(`claude-desktop-asar: ${unpacked.length} unpacked entries verified in ${archive}`);
for (const entry of unpacked) console.log(`claude-desktop-asar: unpacked ${entry}`);
