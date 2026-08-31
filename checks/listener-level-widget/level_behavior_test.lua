local toggles = 0

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

barWidget = {
  render = function(_) end,
}

noctalia = {
  getenv = function(name)
    if name == "XDG_RUNTIME_DIR" then
      return "/run/user/test"
    end
    return nil
  end,
  nowMs = function() return 0 end,
  setUpdateInterval = function(_) end,
  togglePanel = function(id)
    assert(id == "criomos/listener-level:transcript")
    toggles = toggles + 1
  end,
  notify = function(_) error("transcript lifecycle must not notify") end,
  json = { decode = decode },
  runStream = function(command, callback)
    if string.find(command, "/listener/transcript.sock", 1, true) then
      for line in io.lines() do
        callback(line)
      end
    end
    return true
  end,
}

dofile("level.lua")
assert(toggles == 2)
