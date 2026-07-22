const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const fixtures = process.argv[2];
assert.ok(fixtures, "fixture directory argument is required");
const events = JSON.parse(fs.readFileSync(path.join(fixtures, "widget-status-events.json"), "utf8"));

for (const event of events.valid)
  assert.notEqual(validateStatusEvent(event), null, JSON.stringify(event));
for (const event of events.invalid)
  assert.equal(validateStatusEvent(event), null, JSON.stringify(event));

assert.deepEqual(expectedSignal(-55), { quality: "good", qualityColor: "#22c55e", bars: 4 });
assert.deepEqual(expectedSignal(null), { quality: "unavailable", qualityColor: "#6b7280", bars: 0 });

console.log("active-network status validation tests passed");
