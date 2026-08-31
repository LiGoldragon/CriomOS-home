local TranscriptState = require("./TranscriptState.luau")

local function decode(line)
  local session, revision, kind, text = string.match(
    line,
    '^%{"session":"([%w%-]+)","revision":(%d+),"kind":"([a-z]+)","text":"([^"]*)"%}$'
  )
  if session == nil then
    return nil
  end
  return {
    session = session,
    revision = tonumber(revision),
    kind = kind,
    text = text,
  }
end

local function require_event(state, line, expected, expected_kind)
  local accepted, kind = TranscriptState.consume(state, line, decode)
  assert(accepted)
  assert(kind == expected_kind)
  assert(state.text == expected)
end

local state = TranscriptState.new()
for line in io.lines() do
  if line == "MODE transcript" then
    -- The following socket lines exercise the production transition function.
  elseif line == "MODE status" then
    assert(state.text == "")
  elseif string.sub(line, 1, 7) == "STATUS " then
    local accepted = TranscriptState.consume(state, string.sub(line, 8), decode)
    assert(not accepted)
    assert(state.text == "")
  elseif string.sub(line, 1, 6) == "EVENT " then
    local event = string.sub(line, 7)
    if string.find(event, '"revision":2,') then
      require_event(state, event, "Synthetic first", "partial")
    elseif string.find(event, '"revision":1,') then
      local accepted = TranscriptState.consume(state, event, decode)
      assert(not accepted)
      assert(state.text == "Synthetic first")
    elseif string.find(event, '"revision":3,') then
      require_event(state, event, "Synthetic second", "partial")
    elseif string.find(event, '"revision":4,') then
      require_event(state, event, "Synthetic final", "final")
    elseif string.find(event, '"revision":5,') then
      local accepted, kind = TranscriptState.consume(state, event, decode)
      assert(accepted)
      assert(kind == "closed")
      assert(state.text == "")
      assert(state.session == nil)
    else
      error("unexpected test event")
    end
  end
end
