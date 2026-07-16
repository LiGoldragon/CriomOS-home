const assert = require("node:assert/strict");

// Negative solar offsets cross the UTC day boundary without invoking the
// process's civil timezone. This instant is 02:00 in a +02:00 civil zone; the
// former Qt.formatTime path incorrectly displayed that civil-time value.
const instant = Date.parse("2024-01-01T00:30:15Z");
assert.equal(projectedText(instant, -3600), "23:30:15");
assert.notEqual(projectedText(instant, -3600), "01:30:15");
assert.equal(projectedText(instant, 0), "00:30:15");
