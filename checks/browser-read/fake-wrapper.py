#!/usr/bin/env python3
"""Synthetic wrapper/daemon only. Never imports Playwright or opens a browser."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

if sys.argv[1:2] == ["daemon"]:
    if os.environ.get("FIXTURE_MODE") == "ignore-term":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.pause()
    raise SystemExit(0)

mode = os.environ.get("FIXTURE_MODE", "success")
arguments = sys.argv[1:]
session = arguments[1].removeprefix("-s=")
command = arguments[2]
root = Path.cwd()
trace = Path(os.environ["FIXTURE_TRACE"])
with trace.open("a") as log:
    log.write(json.dumps({"root": str(root), "command": command, "arguments": arguments}) + "\n")
# Synthetic preflight models the already-reviewed wrapper boundary.
if os.environ.get("PLAYWRIGHT_MCP_EXTENSION_TOKEN") != "synthetic-token-never-output":
    print("synthetic credential error", file=sys.stderr)
    raise SystemExit(1)
assert not any(key.startswith("PLAYWRIGHT_") and key not in (
    "PLAYWRIGHT_MCP_EXTENSION_TOKEN", "PLAYWRIGHT_MCP_EXECUTABLE_PATH", "PLAYWRIGHT_DAEMON_SESSION_DIR"
) for key in os.environ)
assert "NODE_OPTIONS" not in os.environ and "NODE_PATH" not in os.environ
for key in ("TMPDIR", "XDG_CACHE_HOME", "PLAYWRIGHT_DAEMON_SESSION_DIR", "PWTEST_CLI_GLOBAL_CONFIG"):
    assert Path(os.environ[key]).resolve().is_relative_to(root.resolve())
state = root / "daemon.json"
if command == "attach":
    if mode == "attach-failure":
        print("unrequested snapshot with synthetic-token-never-output")
        raise SystemExit(1)
    daemon = subprocess.Popen([sys.executable, __file__, "daemon"], stdin=subprocess.DEVNULL,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              start_new_session=True)
    state.write_text(json.dumps({"pid": daemon.pid}))
    with trace.open("a") as log:
        log.write(json.dumps({"event": "daemon", "pid": daemon.pid}) + "\n")
    if mode == "attach-timeout":
        signal.pause()
    print(json.dumps({"session": session, "pid": daemon.pid, "result": {"snapshot": "NEVER-FINAL"}}))
elif command == "run-code":
    if "module.exports.closeOwnedPage" in arguments[3]:
        print(json.dumps({"result": json.dumps({"closed": True})}))
    elif mode == "run-timeout":
        if "FIXTURE_EVENT_FIFO" in os.environ:
            with open(os.environ["FIXTURE_EVENT_FIFO"], "w") as event:
                event.write("running\n")
        signal.pause()
    elif mode == "bad-outcome":
        print(json.dumps({"result": json.dumps({"phase": "Read", "values": [{"name": "other", "value": "NEVER-FINAL"}]})}))
    elif mode == "extra-value":
        print(json.dumps({"result": json.dumps({"phase": "Read", "values": [{"name": "title", "value": "ok", "dump": "NEVER-FINAL"}]})}))
    elif mode == "output-overflow":
        print("NEVER-FINAL" * 100000)
    elif mode == "fields":
        print(json.dumps({"result": json.dumps({"phase": "Refused", "refusal": {"Fields": ["title"]}})}))
    elif mode == "tab-cleanup":
        print(json.dumps({"result": json.dumps({"phase": "Refused", "refusal": "TabCleanup"})}))
    else:
        print(json.dumps({"result": json.dumps({"phase": "Read", "values": [{"name": "title", "value": "one » two \\ three\nline"}]})}))
elif command == "detach":
    pid = json.loads(state.read_text())["pid"]
    if mode not in ("daemon-stuck", "ignore-term"):
        os.kill(pid, signal.SIGTERM)
    print(json.dumps({"session": session, "status": "detached"}))
else:
    raise AssertionError(command)
