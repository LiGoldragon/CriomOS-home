local watcher = nil
local current = { state = "unavailable", hands_free = false }
local latest = nil
local interval = nil

barWidget = { render = function(tree) latest = tree end }
noctalia = {
  state = {
    get = function(key) assert(key == "wispr-status-state"); return current end,
    watch = function(key, callback) assert(key == "wispr-status-state"); watcher = callback end,
  },
  nowMs = function() return 0 end,
  setUpdateInterval = function(value) interval = value end,
}

dofile("BarWidget.luau")
assert(watcher ~= nil)
local function icon()
  return latest.children[1].props
end
assert(icon().color == "#6b7280")
local cases = {
  { state = "idle", color = "#e5e7eb", glyph = "󰍬" },
  { state = "recording", color = "#fb7185", glyph = "󰍬" },
  { state = "transcribing", color = "#f59e0b" },
  { state = "error", color = "#ef4444", glyph = "" },
}
for _, expected in ipairs(cases) do
  current = { state = expected.state, hands_free = false }
  watcher(current)
  assert(icon().color == expected.color)
  if expected.glyph then assert(icon().text == expected.glyph) end
end
current = { state = "transcribing", hands_free = false }
watcher(current)
update()
assert(interval == 120)
