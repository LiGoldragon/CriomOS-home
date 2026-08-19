local listener_state = "idle"
local microphone_level = 0.0
local visible_microphone_level = 0.0
local in_flight_count = 0
local connected = false
local success_until_ms = 0
local last_level_event_ms = 0

local function clamp(value, lower, upper)
  return math.max(lower, math.min(upper, value))
end

local function shell_quote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function is_active()
  return listener_state == "starting"
    or listener_state == "recording"
    or listener_state == "finalizing"
    or listener_state == "transcribing"
    or listener_state == "cancelling"
    or in_flight_count > 0
end

local function bar_color(now_ms)
  if now_ms < success_until_ms then
    return "#22c55e"
  end
  if listener_state == "cancelled" then
    return "#38bdf8"
  end
  if listener_state == "starting" or listener_state == "finalizing" or listener_state == "cancelling" then
    return "#f59e0b"
  end
  if listener_state == "transcribing" then
    return "#facc15"
  end
  if listener_state == "recording" or listener_state == "error" then
    return "#ef4444"
  end
  return connected and "#6b7280" or "#374151"
end

local function bar_height(index, now_ms)
  local weights = { 0.48, 0.76, 1.0, 0.76, 0.48 }
  local weight = weights[index]
  if listener_state == "recording" then
    return math.floor(4 + visible_microphone_level * 16 * weight + 0.5)
  end
  if listener_state == "starting" then
    return math.floor(5 + (math.sin(now_ms / 122 + index) + 1.0) * 3 * weight + 0.5)
  end
  if listener_state == "finalizing" or listener_state == "transcribing" or listener_state == "cancelling" then
    return math.floor(7 + (math.sin(now_ms / 122 + index) + 1.0) * 4 * weight + 0.5)
  end
  if now_ms < success_until_ms or listener_state == "cancelled" or listener_state == "error" then
    return 12
  end
  return 4
end

local function render(now_ms)
  local bars = {}
  local color = bar_color(now_ms)
  local visible = is_active() or now_ms < success_until_ms or listener_state == "cancelled" or listener_state == "error" or connected
  for index = 1, 5 do
    table.insert(bars, {
      type = "box",
      key = "level-" .. index,
      props = {
        width = 3,
        height = bar_height(index, now_ms),
        radius = 1.5,
        fill = color,
        opacity = visible and 1.0 or 0.5,
      },
    })
  end

  local children = {
    {
      type = "row",
      key = "levels",
      props = { gap = 2, align = "center" },
      children = bars,
    },
  }
  if in_flight_count > 0 then
    table.insert(children, {
      type = "box",
      key = "in-flight",
      props = { width = 16, height = 16, radius = 8, fill = "#facc15", opacity = 0.9 },
      children = {
        {
          type = "label",
          key = "in-flight-count",
          props = { text = tostring(in_flight_count), color = "#111827", fontSize = 10, fontWeight = "bold" },
        },
      },
    })
  end

  barWidget.render({
    type = "row",
    key = "listener-level",
    props = { height = 22, gap = 4, align = "center" },
    children = children,
  })
end

local function consume_status_message(message)
  local event = noctalia.json.decode(message)
  if type(event) ~= "table" then
    return
  end

  local next_state = type(event.state) == "string" and event.state or "idle"
  local now_ms = noctalia.nowMs()
  if listener_state ~= "delivered" and next_state == "delivered" then
    success_until_ms = now_ms + 700
  elseif next_state ~= "delivered" then
    success_until_ms = 0
  end

  listener_state = next_state
  microphone_level = clamp(tonumber(event.level) or 0.0, 0.0, 1.0)
  in_flight_count = math.max(0, math.floor(tonumber(event.in_flight) or 0))
  connected = true
  if listener_state == "recording" then
    last_level_event_ms = now_ms
    visible_microphone_level = math.max(visible_microphone_level * 0.55, clamp(microphone_level * 2.75, 0.0, 1.0))
  else
    visible_microphone_level = 0.0
  end
  render(now_ms)
end

function update()
  local now_ms = noctalia.nowMs()
  if listener_state == "recording" then
    local level_age_ms = now_ms - last_level_event_ms
    local decay = level_age_ms > 450 and 0.72 or 0.88
    local amplified_level = clamp(microphone_level * 2.75, 0.0, 1.0)
    visible_microphone_level = math.max(level_age_ms > 450 and 0.0 or amplified_level, visible_microphone_level * decay)
    if visible_microphone_level < 0.01 then
      visible_microphone_level = 0.0
    end
  end

  if listener_state == "recording" or now_ms < success_until_ms then
    noctalia.setUpdateInterval(70)
  elseif is_active() then
    noctalia.setUpdateInterval(110)
  else
    noctalia.setUpdateInterval(1000)
  end
  render(now_ms)
end

local runtime_directory = noctalia.getenv("XDG_RUNTIME_DIR") or ""
if runtime_directory ~= "" then
  local socket_path = runtime_directory .. "/listener/status.sock"
  local reconnect_marker = "__listener_socket_disconnected__"
  local command = "while true; do @SOCAT@ -u UNIX-CONNECT:" .. shell_quote(socket_path)
    .. " STDOUT; printf '%s\\n' " .. reconnect_marker .. "; sleep 1; done"
  noctalia.runStream(command, function(line)
    if line == reconnect_marker then
      listener_state = "idle"
      microphone_level = 0.0
      visible_microphone_level = 0.0
      in_flight_count = 0
      connected = false
      render(noctalia.nowMs())
      return
    end
    consume_status_message(line)
  end)
end
