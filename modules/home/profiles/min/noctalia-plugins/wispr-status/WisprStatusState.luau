local State = {}

State.max_line_bytes = 8192
local max_session_bytes = 128
local max_error_bytes = 64
local max_sequence = 9007199254740991
local allowed = { contract = true, type = true, session_id = true, sequence = true, state = true, hands_free = true, error = true }
local states = { idle = true, recording = true, transcribing = true, error = true }

local function valid_event(event)
  if type(event) ~= "table" then return false end
  local count = 0
  for key, _ in pairs(event) do
    if not allowed[key] then return false end
    count = count + 1
  end
  if count < 6 or count > 7 or event.contract ~= "com.criomos.wispr.status.v1" or event.type ~= "snapshot"
    or type(event.session_id) ~= "string" or #event.session_id == 0 or #event.session_id > max_session_bytes
    or type(event.sequence) ~= "number" or event.sequence ~= math.floor(event.sequence) or event.sequence < 0 or event.sequence > max_sequence
    or not states[event.state] or type(event.hands_free) ~= "boolean" then return false end
  if event.error ~= nil and (event.state ~= "error" or type(event.error) ~= "string" or #event.error == 0
    or #event.error > max_error_bytes or not string.match(event.error, "^[a-z0-9_.%-]+$")) then return false end
  return true
end

function State.new()
  return { state = "unavailable", hands_free = false, session_id = nil, sequence = nil, last_session_id = nil,
    last_sequence = nil, retired_sessions = {} }
end

function State.decode(line, decode)
  if type(line) ~= "string" or #line > State.max_line_bytes then return nil end
  local decoded, event = pcall(decode, line)
  if not decoded or not valid_event(event) then return nil end
  return event
end

local function apply(status, event)
  status.session_id, status.sequence = event.session_id, event.sequence
  status.last_session_id, status.last_sequence = event.session_id, event.sequence
  status.state, status.hands_free, status.error = event.state, event.hands_free, event.error
end

function State.consume(status, event)
  if not valid_event(event) or status.retired_sessions[event.session_id] then return false end
  if status.session_id == nil then
    if status.last_session_id ~= nil and event.session_id == status.last_session_id and event.sequence < status.last_sequence then return false end
    if status.last_session_id ~= nil and event.session_id ~= status.last_session_id then status.retired_sessions[status.last_session_id] = true end
    apply(status, event)
    return true
  end
  if event.session_id ~= status.session_id or event.sequence <= status.sequence then return false end
  apply(status, event)
  return true
end

function State.disconnect(status)
  status.session_id, status.sequence = nil, nil
  status.state, status.hands_free, status.error = "unavailable", false, nil
end

function State.public(status)
  return { state = status.state, hands_free = status.hands_free, session_id = status.session_id, sequence = status.sequence, error = status.error }
end

return State
