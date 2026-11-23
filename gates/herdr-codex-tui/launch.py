"""Start the shipped Codex TUI through the exact Herdr agent-start interface."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

herdr, codex, version, shell = sys.argv[1:]
home = Path(os.environ["HOME"])
config = home / "c"
runtime = home / "r"
state = home / "s"
codex_home = home / "codex"
for directory in (config / "herdr", runtime, state, codex_home):
    directory.mkdir(parents=True)

env = {
    "PATH": os.environ["PATH"], "HOME": str(home), "SHELL": shell,
    "TERM": "xterm-256color",
    "XDG_CONFIG_HOME": str(config),
    "XDG_RUNTIME_DIR": str(runtime),
    "XDG_STATE_HOME": str(state),
    "CODEX_HOME": str(codex_home),
}
wrapper = home / "fixture-codex-client"
wrapper.write_text(f"#!{shell}\nexec {shlex.quote(codex)} \"$@\"\n")
wrapper.chmod(0o700)
(config / "herdr" / "config.toml").write_text(
    f"[agents]\ncodex_executables = [{json.dumps(str(wrapper))}]\n"
)
(codex_home / "config.toml").write_text(
    'model = "fixture"\nmodel_provider = "local"\ncheck_for_update_on_startup = false\n'
    '[model_providers.local]\nname = "fixture"\nbase_url = "http://127.0.0.1:9/v1"\n'
    'wire_api = "responses"\nrequires_openai_auth = false\n'
    f'[projects.{json.dumps(str(home))}]\ntrust_level = "trusted"\n'
)

def herdr_call(*arguments):
    result = subprocess.run(
        [herdr, "--session", "witness", *arguments],
        env=env, cwd=home, capture_output=True, text=True, timeout=24,
    )
    stderr = result.stderr
    assert result.returncode == 0, (arguments, result.stdout, stderr)
    reply = json.loads(result.stdout)
    assert "result" in reply, (arguments, reply)
    return reply["result"]

with subprocess.Popen(
    [herdr, "--session", "witness", "server"], env=env, cwd=home,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
) as server:
    try:
        for line in server.stdout:
            if line.startswith("api socket: "):
                socket_path = Path(line.removeprefix("api socket: ").strip())
                assert socket_path.is_relative_to(config)
                assert socket_path.is_socket()
                break
        else:
            raise RuntimeError("isolated Herdr server did not announce its socket")

        pane = herdr_call("workspace", "create", "--cwd", str(home), "--label", "fixture")["root_pane"]
        started = herdr_call(
            "agent", "start", "fixture-flow", "--kind", "codex", "--pane", pane["pane_id"],
            "--timeout", "15000", "--executable", str(wrapper), "--",
            "--no-daemon", "--sandbox", "read-only",
        )
        assert started["type"] == "agent_started"
        assert started["executable"] == str(wrapper)
        agent = started["agent"]
        assert agent["agent"] == "codex" and agent["interactive_ready"] is True
        assert agent["pane_id"] == pane["pane_id"]
        assert agent["terminal_id"] == pane["terminal_id"]
        queried = herdr_call("agent", "get", pane["pane_id"])["agent"]
        assert queried["executable"] == str(wrapper)
        assert queried["terminal_id"] == pane["terminal_id"]
        view = subprocess.check_output(
            [herdr, "--session", "witness", "pane", "read", pane["pane_id"]],
            env=env, cwd=home, text=True, timeout=5,
        )
        assert f"OpenAI Codex (v{version})" in view, view
        print(f"Herdr exact executable and terminal identity confirmed the Codex {version} TUI")
    finally:
        server.terminate()
