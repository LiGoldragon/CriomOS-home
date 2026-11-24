"""Seal or restore a stopped Flow store inside an exclusive writer fence."""

from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def record_of(systemctl, unit):
    fields = [
        "LoadState", "ActiveState", "MainPID", "ControlPID", "Result",
        "ExecMainCode", "ExecMainStatus", "InvocationID",
    ]
    words = subprocess.check_output(
        [systemctl, "--user", "show", *[f"--property={name}" for name in fields], unit],
        text=True,
    )
    return dict(line.split("=", 1) for line in words.splitlines())


def stopped(systemctl, units, runtime):
    owner = {}
    for unit in units:
        record = record_of(systemctl, unit)
        require(
            record.get("LoadState") == "loaded"
            and record.get("ActiveState") in {"inactive", "failed"}
            and record.get("MainPID") == "0"
            and record.get("ControlPID") == "0",
            f"Writer {unit} is not verifiably stopped.",
        )
        owner[unit] = record
    names = ("flow.sock", "flow-meta.sock")
    for name in names:
        path = runtime / name
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError:
            continue
        require(stat.S_ISSOCK(mode), f"Expected a Flow socket at {path}.")
        with socket.socket(socket.AF_UNIX) as connection:
            connection.setblocking(False)
            try:
                connection.connect(str(path))
            except (FileNotFoundError, ConnectionRefusedError):
                continue
        raise SystemExit("A socket owner still serves the Flow place.")
    # Linux retains the original bind address even after Flow renames its
    # listening socket. Recognize an owner before or after that rename.
    for line in Path("/proc/net/unix").read_text().splitlines()[1:]:
        fields = line.split(maxsplit=7)
        if len(fields) == 8:
            path = Path(fields[7])
            require(path.parent != runtime or not any(
                path.name == name or (
                    path.name.startswith(f".{name}.")
                    and path.name.removeprefix(f".{name}.").isdecimal()
                ) for name in names
            ), "A socket owner still serves the Flow place.")
    return owner


def clean_exit(record):
    return (
        record.get("ActiveState"), record.get("Result"),
        record.get("ExecMainCode"), record.get("ExecMainStatus"),
    ) == ("inactive", "success", "1", "0")


def opened(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise SystemExit(f"Expected a regular Flow store file: {path}")
    return os.fdopen(fd, "rb")


def digest(path):
    with opened(path) as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def copy(from_path, to_path, mode):
    with opened(from_path) as source, to_path.open("xb") as target:
        shutil.copyfileobj(source, target)
        os.fchmod(target.fileno(), mode)
        target.flush()
        os.fsync(target.fileno())


def emit(path, record):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(record, stream, sort_keys=True)
        stream.write("\n")
        os.fchmod(stream.fileno(), 0o400)
        stream.flush()
        os.fsync(stream.fileno())


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def sealed(directory, coordinates):
    require(directory.is_dir() and not directory.is_symlink(), "The stopped copy is absent.")
    with opened(directory / "receipt.json") as stream:
        record = json.load(stream)
    require(record["coordinates"] == coordinates, "The stopped copy belongs to another crossing.")
    require(digest(directory / "flow.sema") == record["sha256"], "The stopped copy hash changed.")
    return record


def seal(state, runtime, path, directory, coordinates, exits, systemctl):
    if directory.exists():
        sealed(directory, coordinates)
        require(not (directory / "restored.json").exists(), "This crossing was already reversed.")
        return
    old = exits[coordinates["oldUnit"]]
    scratch = Path(tempfile.mkdtemp(prefix=".flow-seal-", dir=state))
    try:
        snapshot = scratch / "flow.sema"
        copy(path, snapshot, 0o400)
        sha256 = digest(snapshot)
        require(sha256 == digest(path), "The stopped canonical store changed while copying.")
        stopped(systemctl, exits, runtime)
        emit(scratch / "receipt.json", {"coordinates": coordinates, "predecessor": old, "sha256": sha256})
        sync_directory(scratch)
        scratch.rename(directory)
        sync_directory(state)
    finally:
        if scratch.exists():
            shutil.rmtree(scratch)


def restore(state, runtime, path, directory, coordinates, exits, systemctl):
    record = sealed(directory, coordinates)
    restored = directory / "restored.json"
    if restored.exists():
        with opened(restored) as stream:
            require(json.load(stream) == record, "The rollback receipt belongs to another crossing.")
        return
    require(clean_exit(exits[coordinates["newUnit"]]), "The successor did not report a clean graceful exit.")
    # A crash at any partial step leaves a durable artifact and refuses an
    # automatic retry. The old daemon may open only after a complete receipt.
    scratch = Path(tempfile.mkdtemp(prefix=".flow-restore-", dir=state))
    advanced = directory / "successor-closed.sema"
    copy(path, advanced, 0o400)
    sync_directory(directory)
    candidate = scratch / "flow.sema"
    copy(directory / "flow.sema", candidate, 0o600)
    require(digest(candidate) == record["sha256"], "The restored store differs from the stopped copy.")
    stopped(systemctl, exits, runtime)
    candidate.replace(path)
    sync_directory(state)
    emit(scratch / "restored.json", record)
    (scratch / "restored.json").rename(restored)
    sync_directory(directory)
    scratch.rmdir()


@contextmanager
def writer_fence(path):
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        require(stat.S_ISREG(os.fstat(descriptor).st_mode), "Expected a regular Flow writer lock.")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("The exclusive Flow writer fence is held.") from None
        yield
    finally:
        os.close(descriptor)


def main():
    mode, systemctl, state_path, runtime_path, old_unit, new_unit, old_revision, new_revision = sys.argv[1:]
    state, runtime = Path(state_path), Path(runtime_path)
    require(state.is_dir() and runtime.is_dir(), "The Flow place must exist before the handoff.")
    coordinates = dict(oldUnit=old_unit, newUnit=new_unit, oldRevision=old_revision,
                       newRevision=new_revision, runtime=str(runtime), state=str(state))
    path = state / "flow.sema"
    directory = state / f"flow-handoff-{old_unit.removesuffix('.service')}-{new_unit.removesuffix('.service')}"
    with writer_fence(state / "flow-writer.lock"):
        exits = stopped(systemctl, (old_unit, new_unit), runtime)
        action = {"seal": seal, "restore": restore}[mode]
        action(state, runtime, path, directory, coordinates, exits, systemctl)
    print(f"Flow {mode}: stopped-store receipt verified.")


if __name__ == "__main__":
    main()
