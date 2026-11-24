"""Exercise the packaged handoff against synthetic stores and real fences."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile


guard = sys.argv[1]
old_unit = "flow-nexus-departure.service"
new_unit = "flow-nexus-arrival.service"
old = {
    "LoadState": "loaded", "ActiveState": "inactive", "MainPID": "0",
    "ControlPID": "0", "Result": "success", "ExecMainCode": "1",
    "ExecMainStatus": "0", "InvocationID": "departed-invocation",
}
failed = old | {"ActiveState": "failed", "Result": "timeout", "ExecMainCode": "2", "ExecMainStatus": "9"}
new = old | {"InvocationID": "arrival-invocation"}
initial = b'{"requests":["request-a"],"queue":["delivery-a"],"receipts":["receipt-a"]}'
advanced = b'{"requests":["request-b"],"queue":["delivery-b"],"receipts":["receipt-b"]}'


def exercise(root):
    state, runtime = root / "state", root / "runtime"
    state.mkdir()
    runtime.mkdir()
    state_file = state / "flow.sema"
    state_file.write_bytes(initial)
    fence = state / "flow-writer.lock"
    crossing = state / "flow-handoff-flow-nexus-departure-flow-nexus-arrival"
    older = state / "flow-handoff-flow-nexus-0606-flow-nexus-0607"
    older.mkdir()
    (older / "flow.sema").write_bytes(b"older sealed image")
    (older / "receipt.json").write_bytes(b"older receipt")
    older_files = {item.name: item.read_bytes() for item in older.iterdir()}
    unit_info = root / "unit-info.json"
    systemctl = root / "systemctl-fixture"
    systemctl.write_text(f"""#!{sys.executable}
import json
from pathlib import Path
import sys
assert sys.argv[1:3] == ['--user', 'show']
records = json.loads(Path(__file__).with_name('unit-info.json').read_text())
fields = [argument.removeprefix('--property=') for argument in sys.argv[3:-1]]
record = records[sys.argv[-1]]
for field in fields:
    if field in record:
        print(f'{{field}}={{record[field]}}')
""")
    systemctl.chmod(0o700)

    def run(action, departing, arriving=new, refusal=None):
        unit_info.write_text(json.dumps({old_unit: departing, new_unit: arriving}))
        result = subprocess.run(
            [sys.executable, guard, action, str(systemctl), str(state), str(runtime),
             old_unit, new_unit, "old-revision", "new-revision"],
            capture_output=True, text=True, timeout=10,
        )
        if refusal:
            assert result.returncode != 0 and refusal in result.stderr, result
            assert state_file.read_bytes() == (initial if action == "seal" else advanced)
        else:
            assert result.returncode == 0, result

    for unit in (
        failed | {"MainPID": "2345"},
        failed | {"ControlPID": "2345"},
        {key: value for key, value in failed.items() if key != "ControlPID"},
        old | {"LoadState": "not-found"},
        *(old | {"ActiveState": active} for active in ("active", "activating", "deactivating", "reloading")),
    ):
        run("seal", unit, refusal="is not verifiably stopped")
        run("seal", failed, unit, refusal="is not verifiably stopped")
        assert not crossing.exists()

    fence.unlink()
    os.mkfifo(fence, mode=0o600)
    run("seal", failed, refusal="Expected a regular Flow writer lock")
    assert not crossing.exists()
    fence.unlink()
    with fence.open("xb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run("seal", failed, refusal="The exclusive Flow writer fence is held")
        assert not crossing.exists()

    endpoint = runtime / "flow.sock"
    with socket.socket(socket.AF_UNIX) as stream:
        stream.bind(str(endpoint))
        stream.listen()
        run("seal", failed, refusal="A socket owner still serves the Flow place")
        assert not crossing.exists()
    endpoint.unlink()

    run("seal", failed)
    receipt = json.loads((crossing / "receipt.json").read_text())
    assert receipt["predecessor"] == failed
    assert receipt["sha256"] == hashlib.sha256(initial).hexdigest()
    assert (crossing / "flow.sema").read_bytes() == initial
    assert state_file.read_bytes() == initial
    run("seal", failed)

    state_file.write_bytes(advanced)
    # Actual stopped evidence is enough to take a copy, but not permission to
    # throw away the current canonical writer's bytes on an unclean rollback.
    run("restore", old, new | {"ActiveState": "failed"}, refusal="clean graceful exit")
    assert not (crossing / "successor-closed.sema").exists()
    run("restore", old)
    assert state_file.read_bytes() == initial
    assert (crossing / "successor-closed.sema").read_bytes() == advanced
    assert json.loads((crossing / "restored.json").read_text()) == receipt
    assert {item.name: item.read_bytes() for item in older.iterdir()} == older_files


with tempfile.TemporaryDirectory(prefix="handoff-", dir=os.environ.get("TMPDIR", "/tmp")) as directory:
    exercise(Path(directory))
print("Stopped failed writer sealed; live, unfenced and unclean restore cases refused.")
