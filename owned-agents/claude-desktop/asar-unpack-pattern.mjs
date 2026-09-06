// Print the asar `--unpack` pattern that reproduces an archive's own unpacked
// set. Repacking a patched archive without it stores native modules as packed
// entries, and a packed `.node` cannot be dlopen'd, so the pty host dies.
import { readFileSync } from "node:fs";

const [archive] = process.argv.slice(2);
if (!archive) throw new Error("expected an asar archive path");

function readHeader(path) {
  const image = readFileSync(path);
  if (image.length < 16) throw new Error(`not an asar archive: ${path}`);
  const headerSize = image.readUInt32LE(12);
  const end = 16 + headerSize;
  if (end > image.length) throw new Error(`asar header exceeds archive: ${path}`);
  return JSON.parse(image.subarray(16, end).toString("utf8"));
}

function unpackedFiles(header) {
  const found = [];
  (function walk(node, prefix) {
    for (const [name, entry] of Object.entries(node.files ?? {})) {
      const entryPath = prefix ? `${prefix}/${name}` : name;
      if (entry.files) walk(entry, entryPath);
      else if (entry.unpacked) found.push(entryPath);
    }
  })(header, "");
  return found.sort();
}

const upstream = unpackedFiles(readHeader(archive));
if (upstream.length === 0) {
  throw new Error(`asar archive declares no unpacked entries: ${archive}`);
}
const literal = /[*?[\]{}!()]/;
for (const entry of upstream) {
  if (literal.test(entry)) {
    throw new Error(`unpacked entry is not expressible as a literal glob: ${entry}`);
  }
}

// Every native module, plus whatever this archive already kept unpacked.
const alternatives = ["**/*.node", ...upstream.map((entry) => `**/${entry}`)];
const unique = [...new Set(alternatives)];
process.stdout.write(unique.length === 1 ? unique[0] : `{${unique.join(",")}}`);
