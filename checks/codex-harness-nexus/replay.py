"""Run the declared service commands against the pinned binaries in isolation."""

import json
import os
import shlex
import socket
import stat
import subprocess
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text())
root = Path.cwd()
runtime = root / "run"
state = root / "state"
config = root / "config"
place = runtime / "nexus/main"
os.umask(0o077)
for directory in [place, state / "nexus/main", config / "nexus"]:
    directory.mkdir(parents=True)
(config / "nexus/codex-harness-nexus.datom").write_text(plan["config"])
os.environ.update(XDG_RUNTIME_DIR=str(runtime), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(config))

hint = (
    "First ask whose the work is. Work another running thread holds goes to that "
    "thread as a message through Flow. A part of your own piece, a command, a "
    "build, a test, a search, the reading of logs or long files, a body to write, "
    "goes to a sub-agent, reused when one already holds the context; keep your own "
    "context for judgment and the work only you hold. A piece of its own that will "
    "outlast your turn is asked of the Director as a thread."
)

def managed_config(entry):
    args = shlex.split(plan[entry])
    declared = Path(args[args.index("--declared") + 1])
    return args[args.index("--file") + 1], json.loads(declared.read_text())

shared_file, shared = managed_config("sharedHookConfig")
other_file, other = managed_config("foreignHookConfig")
assert shared_file == f"{plan['codexHome']}/config.toml"
assert other_file == f"{Path(plan['codexHome']).parent}/other-codex/config.toml"
assert shared["features"] == {
    "hooks": True, "multi_agent_v2": {"multi_agent_mode_hint_text": hint},
}
assert shared["$hexis"]["modes"] == {
    "/features/hooks": "always",
    "/features/multi_agent_v2/multi_agent_mode_hint_text": "always",
}
assert other["features"] == {"hooks": True}
assert other["$hexis"]["modes"] == {"/features/hooks": "always"}


def words(command):
    return [arg.replace("%t", str(runtime)).replace("%S", str(state)) for arg in shlex.split(command)]

def commands(service, name):
    value = plan[service][name]
    return [value] if isinstance(value, str) else value

def phase(service, name):
    for command in commands(service, name):
        subprocess.run(words(command), check=True, timeout=15)


children = []
try:
    for service in ["nexus", "translator"]:
        phase(service, "ExecStartPre")
        [start] = commands(service, "ExecStart")
        children.append((service, subprocess.Popen(words(start))))
        phase(service, "ExecStartPost")
    for suffix in ["", "-meta", "-translator", "-meta-translator", "-hook", "-emission"]:
        mode = (place / f"codex-harness{suffix}.sock").stat().st_mode
        assert stat.S_ISSOCK(mode) and mode & 0o077 == 0
    marker = place / "codex-harness-translator.ready"
    assert marker.is_file()
    assert (state / "nexus/main/codex-harness-memory-0.4.0.signal").is_file()

    # A second writer at main must be refused without removing its socket.
    pre = subprocess.run(
        words(commands("nexus", "ExecStartPre")[0]), capture_output=True, text=True, timeout=5
    )
    assert pre.returncode and "already owns" in pre.stderr
    assert (place / "codex-harness.sock").is_socket()

    with socket.socket(socket.AF_UNIX) as subscription:
        subscription.settimeout(10)
        subscription.connect(str(place / "codex-harness-translator.sock"))
        subscription.sendall(b"Subscribe")
        subscription.shutdown(socket.SHUT_WR)
        reply = subscription.makefile("r")
        assert reply.readline().startswith("Subscribed.")
        rollout = root / "fixture-rollout.jsonl"
        rollout.touch()
        hook = {
            "hook_event_name": "SessionStart", "source": "startup",
            "session_id": "01234567-1234-7000-8000-123456789abc",
            "transcript_path": str(rollout),
        }
        subprocess.run(
            [plan["hook"], plan["codexHome"]], input=json.dumps(hook),
            text=True, check=True, timeout=5,
        )
        observed = reply.readline()
        assert observed.startswith("Changed.") and "Started" in observed and "Dry" in observed
        reply.close()
finally:
    for service, child in reversed(children):
        child.terminate()
        child.wait(timeout=5)
        phase(service, "ExecStopPost")

assert not list(place.glob("codex-harness*.sock")) and not marker.exists()
print("Both pinned services, private sockets, startup configuration, hook receipt and stop cleanup passed.")
