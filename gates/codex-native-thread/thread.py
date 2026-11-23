"""Exercise the pinned app-server's native identity and JSONL without a model turn."""
import json
import os
from pathlib import Path
import subprocess
import sys

binary, version = sys.argv[1:]
directory = Path(os.environ["HOME"]).resolve()
codex_home = Path(os.environ["CODEX_HOME"]).resolve()
marker = "criomos-native-thread-local-fixture"

with subprocess.Popen(
    [binary, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
    cwd=directory,
) as process:
    def send(message):
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()

    def request(identifier, method, params):
        send({"id": identifier, "method": method, "params": params})
        for line in process.stdout:
            message = json.loads(line)
            if message.get("id") == identifier:
                assert "result" in message, (method, message)
                return message["result"]
        raise RuntimeError(f"No reply to {method}")

    try:
        initialized = request(1, "initialize", {
            "clientInfo": {"name": "criomos-fixture", "version": "1"},
            "capabilities": {"experimentalApi": True},
        })
        assert f"criomos-fixture/{version} " in initialized["userAgent"]
        assert Path(initialized["codexHome"]).resolve() == codex_home
        send({"method": "initialized"})
        start = request(2, "thread/start", {
            "cwd": str(directory),
            "ephemeral": False,
            "sandbox": "read-only",
            "approvalPolicy": "never",
        })["thread"]
        thread_id = start["id"]
        assert start["cliVersion"] == version
        assert start["status"]["type"] == "idle"
        request(3, "thread/inject_items", {
            "threadId": thread_id,
            "items": [{"type": "message", "role": "user",
                       "content": [{"type": "input_text", "text": marker}]}],
        })
        read = request(4, "thread/read", {
            "threadId": thread_id, "includeTurns": True,
        })["thread"]
        assert read["id"] == thread_id
        assert read["path"] == start["path"]
        rollout = Path(read["path"]).resolve()
        assert rollout.is_relative_to(codex_home / "sessions")
        rows = [json.loads(line) for line in rollout.read_text().splitlines()]
        assert rows[0]["type"] == "session_meta"
        assert rows[0]["payload"]["id"] == thread_id
        assert any(
            row["type"] == "response_item"
            and any(item.get("text") == marker for item in row["payload"].get("content", []))
            for row in rows
        ), "native rollout lacks the injected fixture"
        print(f"Codex {version}: initialize, native thread identity, rollout read; no model turn")
    finally:
        process.terminate()
