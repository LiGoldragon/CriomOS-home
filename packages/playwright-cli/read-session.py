"""One owned scope; only a terminal result leaves it after scope completion."""
import errno
import json
import os
from pathlib import Path
import select
import selectors
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid


class Failure(Exception):
    def __init__(self, phase):
        self.phase = phase


def refusal(phase):
    return {"isError": True, "phase": phase}


def remaining(deadline):
    return None if deadline is None else max(0, deadline - time.monotonic())


def exited(descriptor, deadline):
    with selectors.DefaultSelector() as events:
        events.register(descriptor, selectors.EVENT_READ)
        return bool(events.select(remaining(deadline)))


def scope_empty(descriptor, deadline):
    events = select.poll()
    events.register(descriptor, select.POLLPRI | select.POLLERR)
    while True:
        try:
            os.lseek(descriptor, 0, os.SEEK_SET)
            if b"populated 0" in os.read(descriptor, os.fstat(descriptor).st_blksize):
                return True
        except OSError as error:
            # A held kernfs descriptor going offline means this exact cgroup
            # was removed; the kernel permits removal only once it is empty.
            if error.errno == errno.ENODEV:
                return True
            raise
        timeout = remaining(deadline)
        if timeout == 0 or not events.poll(None if timeout is None else timeout * 1000):
            return False


def receive(connection, deadline, bound=None, phase="SessionAttach"):
    data = bytearray()
    with selectors.DefaultSelector() as events:
        events.register(connection, selectors.EVENT_READ)
        while not data.endswith(b"\n"):
            if not events.select(remaining(deadline)):
                raise Failure(phase)
            chunk = connection.recv((bound - len(data) + 1) if bound is not None else os.fstat(connection.fileno()).st_blksize)
            if not chunk:
                raise Failure("SessionRun")
            data.extend(chunk)
            if bound is not None and len(data) > bound:
                raise Failure("SessionRun")
    return json.loads(data)


def send(connection, value):
    connection.sendall(json.dumps(value).encode() + b"\n")


def invoke(command, arguments, environment, deadline, bound, phase):
    child = subprocess.Popen([command, *arguments], stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             env=environment)
    descriptor = os.pidfd_open(child.pid)
    data = bytearray()
    try:
        with selectors.DefaultSelector() as events:
            events.register(descriptor, selectors.EVENT_READ, "exit")
            events.register(child.stdout, selectors.EVENT_READ, "output")
            while events.get_map():
                ready = events.select(remaining(deadline))
                if not ready:
                    raise Failure(phase)
                for event, _ in ready:
                    if event.data == "exit":
                        events.unregister(descriptor)
                    else:
                        chunk = os.read(child.stdout.fileno(), bound - len(data) + 1)
                        if not chunk:
                            events.unregister(child.stdout)
                        else:
                            data.extend(chunk)
                            if len(data) > bound:
                                raise Failure(phase)
        child.wait()
        if child.returncode:
            raise Failure(phase)
        value = json.loads(data)
        if not isinstance(value, dict) or value.get("isError") or isinstance(value.get("result"), dict) and value["result"].get("isError"):
            raise Failure(phase)
        return value
    finally:
        # The controller stops the entire scope, including an unfinished CLI.
        child.stdout.close()
        os.close(descriptor)


def worker(command, address):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(address)
        control_group = next(line[3:] for line in Path("/proc/self/cgroup").read_text().splitlines() if line.startswith("0::"))
        send(connection, {"controlGroup": control_group})
        request = receive(connection, None)
        root = Path(address).parent
        environment = request["environment"]
        limits = request["limits"]
        deadline = request["deadline"]
        session = root.name
        for directory in ("daemon", "tmp", "output", "cache"):
            (root / directory).mkdir()
        (root / "global.json").write_text("{}")
        environment.update({"PWTEST_CLI_GLOBAL_CONFIG": str(root / "global.json"),
                            "PLAYWRIGHT_DAEMON_SESSION_DIR": str(root / "daemon"),
                            "TMPDIR": str(root / "tmp"), "XDG_CACHE_HOME": str(root / "cache")})
        configuration = root / "cli.json"
        configuration.write_text(json.dumps({"outputDir": str(root / "output"),
            "saveSession": False, "saveTrace": False, "saveVideo": False,
            "codegen": "none", "browser": {"initPage": [], "initScript": []},
            "timeouts": {"action": limits["action_ms"], "navigation": limits["navigation_ms"]}}))
        prefix = ["--json", "-s=" + session]
        attached = False
        outcome = refusal("SessionAttach")
        try:
            invoke(command, [*prefix, "attach", "--extension=chrome", "--config=" + str(configuration)], environment, deadline, limits["output_bytes"], "SessionAttach")
            attached = True
            send(connection, {"phase": "SessionRun"})
            value = invoke(command, [*prefix, "run-code", request["readCode"]], environment, deadline, limits["output_bytes"], "SessionRun")
            if not isinstance(value.get("result"), str):
                raise Failure("SessionRun")
            outcome = {"result": value["result"]}
        except Failure as error:
            outcome = refusal(error.phase)
        except Exception:
            outcome = refusal("SessionRun" if attached else "SessionAttach")
        finally:
            if attached:
                send(connection, {"phase": "SessionCleanup"})
                try:
                    invoke(command, [*prefix, "detach"], environment,
                           time.monotonic() + limits["cleanup_ms"] / 1000,
                           limits["output_bytes"], "SessionCleanup")
                except Exception:
                    outcome = refusal("SessionCleanup")
        send(connection, outcome)


def stop_scope(systemctl, unit, deadline):
    child = subprocess.Popen([systemctl, "--user", "stop", unit], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    descriptor = os.pidfd_open(child.pid)
    try:
        if not exited(descriptor, deadline):
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
            child.wait()
            return False
        child.wait()
        return child.returncode == 0
    finally:
        os.close(descriptor)


def supervise(command, systemd_run, systemctl, request):
    limits = request["limits"]
    for name in ("navigation_ms", "action_ms", "command_ms", "cleanup_ms", "output_bytes"):
        if type(limits.get(name)) is not int or limits[name] <= 0:
            raise Failure("ArtifactSetup")
    if not isinstance(request.get("readCode"), str) or not request["readCode"]:
        raise Failure("ArtifactSetup")
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("PLAYWRIGHT_", "PWTEST_")) and key not in ("NODE_OPTIONS", "NODE_PATH")}
    for key in ("PLAYWRIGHT_MCP_EXTENSION_TOKEN", "PLAYWRIGHT_MCP_EXECUTABLE_PATH"):
        if key in os.environ:
            environment[key] = os.environ[key]
    request = {**request, "environment": environment}
    root = None
    launcher = None
    descriptor = None
    group_events = None
    connection = None
    outcome = refusal("ArtifactSetup")
    cleaning = False

    def interrupted(number, frame):
        if not cleaning:
            raise Failure("Interrupted")

    handlers = {number: signal.signal(number, interrupted) for number in (signal.SIGTERM, signal.SIGINT)}
    try:
        root = Path(tempfile.mkdtemp(prefix="browser-read-"))
        unit = "browser-read-" + uuid.uuid4().hex + ".scope"
        address = str(root / "control.sock")
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(address)
            server.listen()
            deadline = time.monotonic() + limits["command_ms"] / 1000
            outcome = refusal("SessionAttach")
            launcher = subprocess.Popen([systemd_run, "--user", "--scope", "--quiet", "--collect",
                "--unit=" + unit, "--property=KillMode=control-group", "--property=SendSIGKILL=yes",
                "--property=TimeoutStopSec=" + str(limits["cleanup_ms"] / 1000),
                "--property=RuntimeMaxSec=" + str((limits["command_ms"] + limits["cleanup_ms"]) / 1000),
                "--", sys.executable, str(Path(__file__).resolve()), "--worker", command, address],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True, cwd=root)
            descriptor = os.pidfd_open(launcher.pid)
            with selectors.DefaultSelector() as events:
                events.register(server, selectors.EVENT_READ, "connection")
                events.register(descriptor, selectors.EVENT_READ, "exit")
                ready = events.select(remaining(deadline))
                if not any(event.data == "connection" for event, _ in ready):
                    raise Failure("SessionAttach")
            connection, _ = server.accept()
            greeting = receive(connection, deadline)
            group = Path(greeting["controlGroup"])
            if not group.is_absolute() or ".." in group.parts or group.name != unit:
                raise Failure("SessionCleanup")
            group_events = os.open(Path("/sys/fs/cgroup") / group.relative_to("/") / "cgroup.events", os.O_RDONLY)
            # Only now is token acquisition/CLI execution granted, inside our scope.
            request["deadline"] = deadline
            send(connection, request)
            phase = "SessionAttach"
            outcome = receive(connection, deadline, limits["output_bytes"], phase)
            if outcome == {"phase": "SessionRun"}:
                phase = "SessionRun"
                outcome = receive(connection, deadline, limits["output_bytes"], phase)
            if outcome == {"phase": "SessionCleanup"}:
                phase = "SessionCleanup"
                outcome = receive(connection, time.monotonic() + limits["cleanup_ms"] / 1000,
                                  limits["output_bytes"], phase)
            if not isinstance(outcome, dict) or not (isinstance(outcome.get("result"), str) or outcome.get("isError") is True):
                raise Failure("SessionRun")
    except Failure as error:
        outcome = refusal(error.phase)
    except Exception:
        # Socket/system-manager/native exceptions never cross the result boundary.
        outcome = refusal("SessionCleanup" if launcher is not None else "ArtifactSetup")
    finally:
        cleaning = True
        if connection is not None:
            connection.close()
        deadline = time.monotonic() + limits["cleanup_ms"] / 1000
        gone = launcher is None
        if launcher is not None:
            if group_events is None:
                # Before the scope handshake, no token/CLI is allowed to start.
                # systemd-run and its ungranted worker retain this launcher group.
                try:
                    os.killpg(launcher.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                gone = exited(descriptor, deadline) if descriptor is not None else launcher.wait() is not None
            else:
                try:
                    stop_scope(systemctl, unit, deadline)
                except Exception:
                    outcome = refusal("SessionCleanup")
                deadline = time.monotonic() + limits["cleanup_ms"] / 1000
                gone = exited(descriptor, deadline) and scope_empty(group_events, deadline)
            if gone:
                launcher.wait()
            else:
                # A cleanup deadline is not an exit acknowledgement. Keep
                # custody and wait for completion events before replying.
                outcome = refusal("SessionCleanup")
                if group_events is not None:
                    scope_empty(group_events, None)
                exited(descriptor, None)
                launcher.wait()
                gone = True
            if descriptor is not None:
                os.close(descriptor)
        if group_events is not None:
            os.close(group_events)
        if root is not None and gone:
            try:
                shutil.rmtree(root)
            except Exception:
                outcome = refusal("ArtifactCleanup")
        for number, handler in handlers.items():
            signal.signal(number, handler)
    return outcome


def main():
    if sys.argv[1] == "--worker":
        worker(*sys.argv[2:])
        return
    try:
        if sys.argv[-1] != "read-session" or len(sys.argv) != 5:
            raise Failure("SessionRun")
        outcome = supervise(*sys.argv[1:4], json.load(sys.stdin))
    except Failure as error:
        outcome = refusal(error.phase)
    except BaseException:
        outcome = refusal("ArtifactSetup")
    print(json.dumps(outcome))


if __name__ == "__main__":
    main()
