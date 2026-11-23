"""Use a loopback-only Anthropic fixture to witness Claude's native hook and JSONL."""
import http.server
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import threading

claude = sys.argv[1]
home = Path(os.environ["HOME"]).resolve()
config_dir = Path(os.environ["CLAUDE_CONFIG_DIR"]).resolve()
marker = "CRIOMOS_CLAUDE_NATIVE_FIXTURE"
config_dir.mkdir(parents=True, exist_ok=True)

hook_file = home / "session-start.json"
hook_code = f"from pathlib import Path; import sys; Path({str(hook_file)!r}).write_text(sys.stdin.read())"
hook_command = shlex.join([sys.executable, "-c", hook_code])
settings = home / "fixture-settings.json"
settings.write_text(json.dumps({"hooks": {"SessionStart": [{
    "hooks": [{"type": "command", "command": hook_command}]
}]}}))
requests = []

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.split("?")[0] != "/v1/messages":
            self.send_error(404)
            return
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        requests.append(body)
        message = {
            "id": "msg_fixture", "type": "message", "role": "assistant",
            "model": body["model"], "content": [], "stop_reason": None,
            "stop_sequence": None, "usage": {"input_tokens": 12, "output_tokens": 0},
        }
        events = [
            ("message_start", {"message": message}),
            ("content_block_start", {"index": 0, "content_block": {"type": "text", "text": ""}}),
            ("content_block_delta", {"index": 0, "delta": {"type": "text_delta", "text": marker}}),
            ("content_block_stop", {"index": 0}),
            ("message_delta", {"delta": {"stop_reason": "end_turn", "stop_sequence": None},
                               "usage": {"output_tokens": 6}}),
            ("message_stop", {}),
        ]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for event, data in events:
            payload = json.dumps({"type": event, **data})
            self.wfile.write(f"event: {event}\ndata: {payload}\n\n".encode())
        self.wfile.flush()

with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        env = dict(os.environ)
        env.update({
            "ANTHROPIC_API_KEY": "local-only-fixture",
            "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{server.server_port}",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "DISABLE_AUTOUPDATER": "1",
        })
        result = subprocess.run([
            claude, "--print", "--output-format", "stream-json", "--verbose",
            "--settings", str(settings), "--tools", "", "--model", "claude-sonnet-4-6",
            "Return the fixture marker.",
        ], cwd=home, env=env, text=True, capture_output=True, timeout=35)
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    finally:
        server.shutdown()
        thread.join()

replies = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
final = next(reply for reply in replies if reply["type"] == "result")
assert final["is_error"] is False and final["result"] == marker
assert requests, "Claude did not reach the local fake model endpoint"
hook = json.loads(hook_file.read_text())
assert hook["hook_event_name"] == "SessionStart"
assert hook["session_id"] == final["session_id"]
native = Path(hook["transcript_path"]).resolve()
assert native.is_relative_to(config_dir)
transcript = [json.loads(line) for line in native.read_text().splitlines()]
assert any(
    row.get("type") == "assistant"
    and row.get("sessionId") == final["session_id"]
    and any(part.get("text") == marker for part in row["message"]["content"])
    for row in transcript
), "native Claude transcript did not carry the bound assistant fixture"
print("Claude SessionStart, native session identity and transcript passed on loopback only")
