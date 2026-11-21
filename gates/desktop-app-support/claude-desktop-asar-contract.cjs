const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const [asarModule, vendor, packaged, claudeCode] = process.argv.slice(2);
const asar = require(asarModule);
const entries = (archive) => asar.listPackage(archive).sort();
const vendorEntries = entries(vendor);
assert.deepEqual(entries(packaged), vendorEntries, "ASAR entry list differs");

const vendorInitializer = "this.localBinaryInitPromise=null";
const localInitializer =
  "this.localBinaryInitPromise=this.initLocalBinary(" +
  JSON.stringify(claudeCode) +
  ")";
let changedManagers = 0;

for (const entry of vendorEntries) {
  const name = entry.slice(1);
  const before = asar.statFile(vendor, name, false);
  const after = asar.statFile(packaged, name, false);
  assert.equal(Boolean(after.files), Boolean(before.files), `${name}: directory`);
  assert.equal(after.link, before.link, `${name}: link target`);
  assert.equal(Boolean(after.unpacked), Boolean(before.unpacked), `${name}: unpacked`);
  assert.equal(Boolean(after.executable), Boolean(before.executable), `${name}: executable`);
  if (before.files || before.link) continue;

  if (before.unpacked) {
    // Unpacked binaries get Nix's ELF fixups outside the archive.
    assert.equal(after.size, before.size, `${name}: archive metadata size`);
    const installed = fs.statSync(path.join(`${packaged}.unpacked`, name));
    assert.ok(installed.isFile() && installed.size > 0, `${name}: unpacked file`);
    continue;
  }

  const vendorBytes = asar.extractFile(vendor, name, false);
  const packagedBytes = asar.extractFile(packaged, name, false);
  if (packagedBytes.equals(vendorBytes)) continue;

  assert.match(name, /^\.vite\/build\/index\.chunk-[\w-]+\.js$/, "modified packed entry");
  const source = vendorBytes.toString("utf8");
  assert.equal(source.split(vendorInitializer).length, 2, `${name}: vendor initializer`);
  const expected = Buffer.from(source.replace(vendorInitializer, () => localInitializer));
  assert.ok(packagedBytes.equals(expected), `${name}: local manager initializer`);
  changedManagers++;
}

assert.equal(changedManagers, 1, "exactly one packed manager must change");
