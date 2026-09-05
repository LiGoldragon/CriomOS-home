local current = noctalia.state.get("wispr-status-state") or { state = "unavailable", hands_free = false }
local microphone_level = 0.0
local visible_microphone_level = 0.0
local last_microphone_sequence = nil
local last_microphone_sample_ms = nil
local last_session_id = nil

local function clamp(value, lower, upper)
  return math.max(lower, math.min(upper, value))
end

local function visual(now_ms)
  if current.state == "idle" then return "󰍬", "#e5e7eb" end
  if current.state == "recording" then return "󰍬", "#fb7185" end
  if current.state == "transcribing" then return math.floor(now_ms / 240) % 2 == 0 and "󰔟" or "󰔠", "#f59e0b" end
  if current.state == "error" then return "", "#ef4444" end
  return "󰍭", "#6b7280"
end

local function consume_microphone(now_ms)
  if current.session_id ~= last_session_id then
    last_session_id = current.session_id
    last_microphone_sequence = nil
  end
  local microphone = current.microphone
  if current.state ~= "recording" or type(microphone) ~= "table" or type(microphone.sequence) ~= "number"
    or microphone.sequence ~= math.floor(microphone.sequence) or microphone.sequence < 0 then
    microphone_level, visible_microphone_level, last_microphone_sample_ms = 0.0, 0.0, nil
    return
  end
  if last_microphone_sequence ~= nil and microphone.sequence <= last_microphone_sequence then return end
  last_microphone_sequence = microphone.sequence
  if microphone.capture == "available" and type(microphone.rms) == "number" and microphone.rms >= 0 and microphone.rms <= 1 then
    microphone_level = microphone.rms
    visible_microphone_level = clamp(microphone_level * 2.75, 0.0, 1.0)
    last_microphone_sample_ms = now_ms
  else
    microphone_level, visible_microphone_level, last_microphone_sample_ms = 0.0, 0.0, nil
  end
end

local function meter_is_active(now_ms)
  return current.state == "recording" and last_microphone_sample_ms ~= nil and now_ms - last_microphone_sample_ms <= 450
    and visible_microphone_level > 0
end

local function bar_height(index, now_ms)
  local weights = { 0.48, 0.76, 1.0, 0.76, 0.48 }
  local level = meter_is_active(now_ms) and visible_microphone_level or 0.0
  return math.floor(4 + level * 16 * weights[index] + 0.5)
end

local function render(now_ms)
  local glyph, color = visual(now_ms)
  local children = {
    { type = "label", key = "wispr-status-icon", props = { text = glyph, color = color, fontSize = 16 } },
  }
  if current.state == "recording" then
    local bars = {}
    local meter_color = meter_is_active(now_ms) and "#fb7185" or "#6b7280"
    for index = 1, 5 do
      table.insert(bars, {
        type = "box",
        key = "wispr-meter-" .. index,
        props = { width = 3, height = bar_height(index, now_ms), radius = 1.5, fill = meter_color },
      })
    end
    table.insert(children, {
      type = "row",
      key = "wispr-status-meter",
      props = { gap = 2, align = "center" },
      children = bars,
    })
  end
  barWidget.render({
    type = "row",
    key = "wispr-status",
    props = { height = 22, gap = current.state == "recording" and 4 or 0, align = "center" },
    children = children,
  })
end

noctalia.state.watch("wispr-status-state", function(value)
  if type(value) == "table" then current = value else current = { state = "unavailable", hands_free = false } end
  consume_microphone(noctalia.nowMs())
  render(noctalia.nowMs())
end)

function update()
  local now_ms = noctalia.nowMs()
  if current.state == "recording" and last_microphone_sample_ms ~= nil and now_ms - last_microphone_sample_ms > 450 then
    visible_microphone_level = 0.0
  end
  noctalia.setUpdateInterval(current.state == "recording" and 70 or (current.state == "transcribing" and 120 or 1000))
  render(now_ms)
end

consume_microphone(noctalia.nowMs())
render(noctalia.nowMs())
