local State = dofile("WisprStatusState.luau")

local function event(session, sequence, state, hands_free, error)
  local value = {
    contract = "com.criomos.wispr.status.v1",
    type = "snapshot",
    session_id = session,
    sequence = sequence,
    state = state,
    hands_free = hands_free,
  }
  if error ~= nil then
    value.error = error
  end
  return value
end

local status = State.new()
assert(status.state == "unavailable")
assert(State.consume(status, event("first", 1, "recording", false)))
assert(status.state == "recording")
assert(status.session_id == "first")
assert(not State.consume(status, event("first", 1, "idle", false)))
assert(not State.consume(status, event("first", 0, "idle", false)))
assert(not State.consume(status, event("first", 2, "unknown", false)))
assert(not State.consume(status, event("first", 2, "error", false, "not safe!")))
assert(not State.consume(status, {
  contract = "com.criomos.wispr.status.v1",
  type = "snapshot",
  session_id = "first",
  sequence = 2,
  state = "idle",
  hands_free = false,
  surprise = true,
}))
assert(State.consume(status, event("first", 2, "transcribing", true)))
assert(status.hands_free)

State.disconnect(status)
assert(status.state == "unavailable")
assert(State.consume(status, event("first", 2, "transcribing", true)))
State.disconnect(status)
assert(State.consume(status, event("second", 1, "idle", false)))
State.disconnect(status)
assert(not State.consume(status, event("first", 3, "recording", false)))
assert(status.state == "unavailable")
assert(not State.decode(string.rep("x", 8193), function(_) return {} end))
