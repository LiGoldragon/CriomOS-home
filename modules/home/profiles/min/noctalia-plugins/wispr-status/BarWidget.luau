local current = noctalia.state.get("wispr-status") or { state = "unavailable", hands_free = false }

local function visual(now_ms)
  if current.state == "idle" then return "󰍬", "#e5e7eb" end
  if current.state == "recording" then return "󰍬", "#fb7185" end
  if current.state == "transcribing" then return math.floor(now_ms / 240) % 2 == 0 and "󰔟" or "󰔠", "#f59e0b" end
  if current.state == "error" then return "", "#ef4444" end
  return "󰍭", "#6b7280"
end

local function render(now_ms)
  local glyph, color = visual(now_ms)
  barWidget.render({
    type = "row",
    key = "wispr-status",
    props = { height = 22, align = "center" },
    children = {
      { type = "label", key = "wispr-status-icon", props = { text = glyph, color = color, fontSize = 16 } },
    },
  })
end

noctalia.state.watch("wispr-status", function(value)
  if type(value) == "table" then current = value else current = { state = "unavailable", hands_free = false } end
  render(noctalia.nowMs())
end)

function update()
  noctalia.setUpdateInterval(current.state == "transcribing" and 120 or 1000)
  render(noctalia.nowMs())
end

render(noctalia.nowMs())
