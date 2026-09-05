local State = require("./WisprStatusState.luau")

local stale_after_ms = 5000
local disconnected = "__wispr_status_socket_disconnected__"
local status = State.new()
local last_event_ms = nil
local last_published = nil

local function shell_quote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end
local function publish()
  local value = State.public(status)
  if last_published ~= nil and last_published.state == value.state
    and last_published.hands_free == value.hands_free and last_published.error == value.error then return end
  last_published = value
  noctalia.state.set("wispr-status-state", value)
end
local function unavailable()
  State.disconnect(status)
  last_event_ms = nil
  publish()
end
local function consume(line)
  if line == disconnected then unavailable(); return end
  local event = State.decode(line, noctalia.json.decode)
  if event ~= nil and State.consume(status, event) then last_event_ms = noctalia.nowMs(); publish() end
end

local runtime_directory = noctalia.getenv("XDG_RUNTIME_DIR") or ""
if runtime_directory ~= "" then
  local socket_path = runtime_directory .. "/wispr-flow-status-v1.sock"
  local command = "while true; do @SOCAT@ -u UNIX-CONNECT:" .. shell_quote(socket_path)
    .. " STDOUT; printf '%s\\n' " .. disconnected .. "; sleep 1; done"
  noctalia.runStream(command, consume)
end

function update()
  if last_event_ms ~= nil and noctalia.nowMs() - last_event_ms > stale_after_ms then unavailable() end
  noctalia.setUpdateInterval(1000)
end

publish()
