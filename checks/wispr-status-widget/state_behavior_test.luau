local State = dofile("WisprStatusState.luau")

local function microphone(sequence, capture, rms)
  return { sequence = sequence, capture = capture, rms = rms }
end

local function event(session, sequence, state, hands_free, microphone_value, error)
  local value = {
    contract = "com.criomos.wispr.status.v2",
    type = "snapshot",
    session_id = session,
    sequence = sequence,
    state = state,
    hands_free = hands_free,
    microphone = microphone_value,
  }
  if error ~= nil then value.error = error end
  return value
end

local status = State.new()
local accepted, microphone_fresh = State.consume(status, event("first", 1, "recording", false, microphone(1, "available", 0.5)))
assert(accepted and microphone_fresh)
assert(status.state == "recording")
assert(status.microphone.capture == "available" and status.microphone.rms == 0.5)
assert(not State.consume(status, event("first", 1, "idle", false, microphone(1, "available", 0.5))))

accepted, microphone_fresh = State.consume(status, event("first", 2, "recording", false, microphone(1, "available", 0.5)))
assert(accepted and not microphone_fresh)
assert(status.microphone.sequence == 1)
accepted, microphone_fresh = State.consume(status, event("first", 3, "recording", false, microphone(2, "available", 0.5)))
assert(accepted and microphone_fresh)
assert(status.microphone.sequence == 2 and status.microphone.rms == 0.5)
accepted, microphone_fresh = State.consume(status, event("first", 4, "recording", false, microphone(3, "available", 0)))
assert(accepted and microphone_fresh)
assert(status.microphone.capture == "available" and status.microphone.rms == 0)
accepted, microphone_fresh = State.consume(status, event("first", 5, "recording", false, microphone(4, "unavailable", nil)))
assert(accepted and microphone_fresh)
assert(status.microphone.capture == "unavailable" and status.microphone.rms == nil)

accepted, microphone_fresh = State.consume(status, event("first", 6, "recording", false, microphone(3, "available", 1)))
assert(accepted and not microphone_fresh)
assert(status.microphone.sequence == 4 and status.microphone.capture == "unavailable")
assert(not State.consume(status, event("first", 7, "recording", false, microphone(5, "available", 1.1))))
assert(not State.consume(status, event("first", 7, "recording", false, { sequence = 5, capture = "unavailable", rms = 0 })))
assert(not State.consume(status, event("first", 7, "recording", false, { sequence = 5, capture = "available" })))
assert(not State.consume(status, event("first", 7, "recording", false, { sequence = 5, capture = "available", rms = 0.5, extra = true })))

State.disconnect(status)
assert(status.state == "unavailable")
assert(status.microphone.capture == "unavailable" and status.microphone.rms == nil)
accepted, microphone_fresh = State.consume(status, event("first", 7, "recording", false, microphone(4, "unavailable", nil)))
assert(accepted and microphone_fresh)
accepted, microphone_fresh = State.consume(status, event("first", 8, "recording", false, microphone(5, "available", 0.25)))
assert(accepted and microphone_fresh)

State.disconnect(status)
accepted, microphone_fresh = State.consume(status, event("first", 8, "recording", false, microphone(5, "available", 0.25)))
assert(accepted and microphone_fresh)
assert(status.microphone.capture == "available" and status.microphone.rms == 0.25)

State.disconnect(status)
accepted, microphone_fresh = State.consume(status, event("second", 1, "idle", false, microphone(0, "unavailable", nil)))
assert(accepted and microphone_fresh)
assert(not State.decode(string.rep("x", 8193), function(_) return {} end))
