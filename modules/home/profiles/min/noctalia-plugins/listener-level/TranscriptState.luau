local TranscriptState = {}

local max_line_bytes = 8192
local max_session_bytes = 128
local max_text_bytes = 4096
local max_revision = 9007199254740991

local function valid_event(event)
  if type(event) ~= "table" then
    return false
  end

  local field_count = 0
  for key, _ in pairs(event) do
    if key ~= "session" and key ~= "revision" and key ~= "kind" and key ~= "text" then
      return false
    end
    field_count = field_count + 1
  end
  if field_count ~= 4 then
    return false
  end

  if type(event.session) ~= "string" or #event.session == 0 or #event.session > max_session_bytes then
    return false
  end
  if type(event.revision) ~= "number" or event.revision ~= math.floor(event.revision)
    or event.revision < 0 or event.revision > max_revision then
    return false
  end
  if event.kind ~= "partial" and event.kind ~= "final" and event.kind ~= "error" and event.kind ~= "closed" then
    return false
  end
  if type(event.text) ~= "string" or #event.text > max_text_bytes then
    return false
  end
  return true
end

function TranscriptState.new()
  return {
    session = nil,
    revision = -1,
    kind = nil,
    text = "",
  }
end

function TranscriptState.clear(state)
  state.session = nil
  state.revision = -1
  state.kind = nil
  state.text = ""
end

function TranscriptState.consume(state, line, decode)
  if type(line) ~= "string" or #line > max_line_bytes then
    return false, nil
  end

  local decoded, event = pcall(decode, line)
  if not decoded or not valid_event(event) then
    return false, nil
  end

  if state.session ~= nil and event.session ~= state.session then
    return false, nil
  end
  if state.session ~= nil and event.revision <= state.revision then
    return false, nil
  end

  state.session = event.session
  state.revision = event.revision
  state.kind = event.kind
  if event.kind == "partial" or event.kind == "final" then
    state.text = event.text
  else
    TranscriptState.clear(state)
  end
  return true, event.kind
end

return TranscriptState
