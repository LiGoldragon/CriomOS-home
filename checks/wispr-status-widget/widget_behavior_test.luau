local watcher = nil
local now = 0
local current = { state = "unavailable", hands_free = false, microphone = { sequence = 0, capture = "unavailable", rms = nil } }
local latest = nil
local interval = nil

barWidget = { render = function(tree) latest = tree end }
noctalia = {
  state = {
    get = function(key) assert(key == "wispr-status-state"); return current end,
    watch = function(key, callback) assert(key == "wispr-status-state"); watcher = callback end,
  },
  nowMs = function() return now end,
  setUpdateInterval = function(value) interval = value end,
}

dofile("BarWidget.luau")
assert(watcher ~= nil)
local function icon() return latest.children[1].props end
local function meter() return latest.children[2] end
local function bars() return meter().children end
assert(icon().color == "#6b7280")

current = { state = "recording", hands_free = false, microphone = { sequence = 1, capture = "available", rms = 0.4 } }
watcher(current)
assert(icon().color == "#fb7185" and icon().text == "󰍬")
assert(latest.props.height == 22 and meter().props.gap == 2 and #bars() == 5)
assert(bars()[1].props.width == 3 and bars()[1].props.height == 10 and bars()[2].props.height == 14 and bars()[3].props.height == 17)
assert(bars()[3].props.fill == "#fb7185")

now = 400
current = { state = "recording", hands_free = false, microphone = { sequence = 1, capture = "available", rms = 0.4 } }
watcher(current)
update()
assert(bars()[3].props.height == 17 and interval == 70)
now = 451
update()
assert(bars()[1].props.height == 4 and bars()[3].props.height == 4 and bars()[3].props.fill == "#6b7280")

now = 500
current = { state = "recording", hands_free = false, microphone = { sequence = 2, capture = "available", rms = 0.4 } }
watcher(current)
assert(bars()[3].props.height == 17)
now = 550
current = { state = "recording", hands_free = false, microphone = { sequence = 3, capture = "available", rms = 0.01 } }
watcher(current)
assert(bars()[1].props.height == 6 and bars()[3].props.height == 9 and bars()[3].props.fill == "#fb7185")
now = 600
current = { state = "recording", hands_free = false, microphone = { sequence = 4, capture = "available", rms = 0 } }
watcher(current)
assert(bars()[1].props.height == 4 and bars()[3].props.height == 4 and bars()[3].props.fill == "#6b7280")
now = 700
current = { state = "recording", hands_free = false, microphone = { sequence = 6, capture = "unavailable", rms = nil } }
watcher(current)
assert(bars()[1].props.height == 4 and bars()[3].props.height == 4 and bars()[3].props.fill == "#6b7280")

local cases = {
  { state = "idle", color = "#e5e7eb", glyph = "󰍬" },
  { state = "transcribing", color = "#f59e0b" },
  { state = "error", color = "#ef4444", glyph = "" },
}
for _, expected in ipairs(cases) do
  current = { state = expected.state, hands_free = false, microphone = { sequence = 6, capture = "unavailable", rms = nil } }
  watcher(current)
  assert(icon().color == expected.color)
  if expected.glyph then assert(icon().text == expected.glyph) end
end
assert(latest.props.width == nil)
