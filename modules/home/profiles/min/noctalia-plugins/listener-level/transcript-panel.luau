local TranscriptState = require("./TranscriptState.luau")

local transcript = TranscriptState.new()

local function shell_quote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function render()
  local visible = transcript.kind == "partial" or transcript.kind == "final"
  panel.render({
    type = "column",
    key = "listener-transcript-panel",
    props = {
      padding = 18,
      gap = 10,
      visible = visible,
    },
    children = {
      {
        type = "label",
        key = "listener-transcript-heading",
        props = {
          text = transcript.kind == "final" and "Listener transcript" or "Listening…",
          fontSize = 13,
          fontWeight = "bold",
          color = "primary",
        },
      },
      {
        type = "label",
        key = "listener-transcript-text",
        props = {
          text = transcript.text,
          fontSize = 18,
          wrap = true,
          color = "foreground",
        },
      },
    },
  })
end

local runtime_directory = noctalia.getenv("XDG_RUNTIME_DIR") or ""
if runtime_directory ~= "" then
  local socket_path = runtime_directory .. "/listener/transcript.sock"
  local reconnect_marker = "__listener_transcript_socket_disconnected__"
  local command = "while true; do @SOCAT@ -u UNIX-CONNECT:" .. shell_quote(socket_path)
    .. " STDOUT; printf '%s\\n' " .. reconnect_marker .. "; sleep 1; done"
  noctalia.runStream(command, function(line)
    if line == reconnect_marker then
      TranscriptState.clear(transcript)
      render()
      panel.close()
      return
    end

    local accepted, kind = TranscriptState.consume(transcript, line, noctalia.json.decode)
    if not accepted then
      return
    end
    render()
    if kind == "closed" or kind == "error" then
      panel.close()
    end
  end)
end

render()
