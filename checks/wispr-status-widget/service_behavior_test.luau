local now = 0
local stream_callback = nil
local current = nil
local writes = 0

noctalia = {
  getenv = function(name)
    if name == "XDG_RUNTIME_DIR" then return "/run/user/test" end
    return nil
  end,
  nowMs = function() return now end,
  setUpdateInterval = function(_) end,
  json = {
    decode = function(line)
      local session, sequence, state, hands = string.match(
        line,
        '^%{"contract":"com%.criomos%.wispr%.status%.v1","type":"snapshot","session_id":"([%w%-]+)","sequence":(%d+),"state":"([a-z]+)","hands_free":([a-z]+)%}$'
      )
      if session == nil then return nil end
      return {
        contract = "com.criomos.wispr.status.v1", type = "snapshot", session_id = session,
        sequence = tonumber(sequence), state = state, hands_free = hands == "true",
      }
    end,
  },
  state = {
    set = function(key, value)
      assert(key == "wispr-status-state")
      current = value
      writes = writes + 1
    end,
  },
  runStream = function(_, callback)
    stream_callback = callback
  end,
}

package.preload["./WisprStatusState.luau"] = function()
  return dofile("WisprStatusState.luau")
end
dofile("WisprStatusService.luau")
assert(current.state == "unavailable")
assert(stream_callback ~= nil)
stream_callback('{"contract":"com.criomos.wispr.status.v1","type":"snapshot","session_id":"alpha","sequence":1,"state":"recording","hands_free":false}')
assert(current.state == "recording")
local accepted_writes = writes
stream_callback('{"contract":"com.criomos.wispr.status.v1","type":"snapshot","session_id":"alpha","sequence":1,"state":"idle","hands_free":false}')
stream_callback('{"contract":"wrong","type":"snapshot","session_id":"alpha","sequence":2,"state":"idle","hands_free":false}')
stream_callback(string.rep("x", 9000))
assert(writes == accepted_writes)
stream_callback("__wispr_status_socket_disconnected__")
assert(current.state == "unavailable")
stream_callback('{"contract":"com.criomos.wispr.status.v1","type":"snapshot","session_id":"beta","sequence":1,"state":"transcribing","hands_free":true}')
assert(current.state == "transcribing" and current.hands_free)
stream_callback("__wispr_status_socket_disconnected__")
stream_callback('{"contract":"com.criomos.wispr.status.v1","type":"snapshot","session_id":"alpha","sequence":2,"state":"recording","hands_free":false}')
assert(current.state == "unavailable")
stream_callback('{"contract":"com.criomos.wispr.status.v1","type":"snapshot","session_id":"gamma","sequence":1,"state":"error","hands_free":false}')
assert(current.state == "error")
now = now + 6000
update()
assert(current.state == "unavailable")
