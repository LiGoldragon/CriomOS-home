local now = 0
local stream_callback = nil
local current = nil
local writes = 0

local function microphone(sequence, capture, rms)
  return { sequence = sequence, capture = capture, rms = rms }
end

local function snapshot(sequence, state, microphone_value)
  return {
    contract = "com.criomos.wispr.status.v2", type = "snapshot", session_id = "alpha",
    sequence = sequence, state = state, hands_free = false, microphone = microphone_value,
  }
end

local frames = {
  recording = snapshot(1, "recording", microphone(1, "available", 0.4)),
  heartbeat = snapshot(2, "recording", microphone(1, "available", 0.4)),
  same_rms_fresh = snapshot(3, "recording", microphone(2, "available", 0.4)),
  heartbeat_after_sample = snapshot(4, "recording", microphone(2, "available", 0.4)),
  out_of_order_microphone = snapshot(5, "recording", microphone(1, "available", 1)),
  invalid_microphone = snapshot(6, "recording", { sequence = 3, capture = "available", rms = 2 }),
  silence = snapshot(7, "recording", microphone(3, "available", 0)),
  unavailable = snapshot(8, "recording", microphone(4, "unavailable", nil)),
}

noctalia = {
  getenv = function(name) if name == "XDG_RUNTIME_DIR" then return "/run/user/test" end end,
  nowMs = function() return now end,
  setUpdateInterval = function(_) end,
  json = { decode = function(line) return frames[line] end },
  state = {
    set = function(key, value)
      assert(key == "wispr-status-state")
      current = value
      writes = writes + 1
    end,
  },
  runStream = function(_, callback) stream_callback = callback end,
}

package.preload["./WisprStatusState.luau"] = function() return dofile("WisprStatusState.luau") end
dofile("WisprStatusService.luau")
assert(current.state == "unavailable")
assert(stream_callback ~= nil)

stream_callback("recording")
assert(current.state == "recording" and current.microphone.sequence == 1)
local recording_writes = writes
now = 400
stream_callback("heartbeat")
assert(writes == recording_writes)
now = 500
stream_callback("same_rms_fresh")
assert(current.microphone.sequence == 2 and writes == recording_writes + 1)
local fresh_writes = writes
now = 700
stream_callback("heartbeat_after_sample")
assert(writes == fresh_writes)

stream_callback("out_of_order_microphone")
assert(current.microphone.sequence == 2 and writes == fresh_writes)
stream_callback("invalid_microphone")
assert(current.microphone.sequence == 2 and writes == fresh_writes)
now = 5601
update()
assert(current.state == "recording")
now = 5701
stream_callback("silence")
assert(current.microphone.capture == "available" and current.microphone.rms == 0)
stream_callback("unavailable")
assert(current.microphone.capture == "unavailable" and current.microphone.rms == nil)

stream_callback("__wispr_status_socket_disconnected__")
assert(current.state == "unavailable" and current.microphone.capture == "unavailable")
