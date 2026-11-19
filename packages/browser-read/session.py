"""One private, bounded wrapper session. No Datom or credentials are decoded here."""
import ctypes
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.parse
import uuid


class PhaseFailure(Exception):
    def __init__(self, phase):
        self.phase = phase


class Interrupted(BaseException):
    pass


def refused(phase):
    return {"phase": "Refused", "refusal": phase}


class Session:
    def __init__(self, wrapper, task):
        self.wrapper = wrapper
        self.task = task
        self.root = None
        self.environment = None
        self.session = "browser-read-" + uuid.uuid4().hex
        self.task["marker"] = self.session
        self.pidfds = {}
        self.cleaning = False
        self.started = False
        self.attached = False
        self.running = False
        self.interrupted = False
        self.deadline = time.monotonic() + task["limits"]["command_ms"] / 1000

    def on_signal(self, number, frame):
        self.interrupted = True
        if not self.cleaning:
            raise Interrupted()

    def adopt(self):
        # This process has been made a Linux child subreaper before any launch.
        # A completed frontend reparents its detached daemon here. /proc is read
        # once in response to that exit, not scanned for an unrelated process.
        children = Path(f"/proc/self/task/{os.getpid()}/children").read_text().split()
        for child in children:
            pid = int(child)
            if pid not in self.pidfds:
                self.pidfds[pid] = os.pidfd_open(pid)

    def await_exit(self, descriptor, milliseconds):
        with selectors.DefaultSelector() as events:
            events.register(descriptor, selectors.EVENT_READ)
            return bool(events.select(milliseconds / 1000))

    def terminate(self, descriptor):
        limit = self.task["limits"]["cleanup_ms"]
        if self.await_exit(descriptor, 0):
            return
        try:
            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if self.await_exit(descriptor, limit):
            return
        try:
            signal.pidfd_send_signal(descriptor, signal.SIGKILL)
        except ProcessLookupError:
            pass
        if not self.await_exit(descriptor, limit):
            raise PhaseFailure("SessionCleanup")

    def invoke(self, arguments, milliseconds):
        if milliseconds <= 0:
            raise PhaseFailure("SessionRun")
        child = subprocess.Popen(
            [self.wrapper, "--json", "-s=" + self.session, *arguments],
            cwd=self.root, env=self.environment, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        descriptor = os.pidfd_open(child.pid)
        output = bytearray()
        completed = False
        deadline = time.monotonic() + milliseconds / 1000
        try:
            with selectors.DefaultSelector() as events:
                events.register(child.stdout, selectors.EVENT_READ, "output")
                events.register(descriptor, selectors.EVENT_READ, "exit")
                while events.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise PhaseFailure("SessionRun")
                    ready = events.select(remaining)
                    if not ready:
                        raise PhaseFailure("SessionRun")
                    for event, _ in ready:
                        if event.data == "exit":
                            completed = True
                            events.unregister(descriptor)
                        else:
                            chunk = os.read(child.stdout.fileno(), self.task["limits"]["output_bytes"] - len(output) + 1)
                            if not chunk:
                                events.unregister(child.stdout)
                            else:
                                output.extend(chunk)
                                if len(output) > self.task["limits"]["output_bytes"]:
                                    raise PhaseFailure("SessionRun")
            child.wait()
            if child.returncode != 0:
                raise PhaseFailure("SessionRun")
            value = json.loads(output)
            if not isinstance(value, dict) or value.get("isError") or isinstance(value.get("result"), dict) and value["result"].get("isError"):
                raise PhaseFailure("SessionRun")
            return value
        finally:
            # A frontend timeout is cancellation, never proof of tab cleanup.
            # SIGTERM is forwarded during CLI startup; pidfd pins the exact PID.
            if not completed:
                self.terminate(descriptor)
            child.wait()
            child.stdout.close()
            os.close(descriptor)
            self.adopt()

    def code(self, name):
        source = Path(__file__).with_name("read-page.cjs").read_text()
        # The fixed module is wrapped to return its exported function. No
        # request or registry string is inserted as code, only JSON literals.
        return "async page => { const module = {exports:{}}; " + source + "; return await module.exports." + name + "(page," + json.dumps(self.task) + "); }"

    def setup(self):
        (self.root / ".playwright").mkdir()
        for name in ("daemon", "tmp", "output", "cache"):
            (self.root / name).mkdir()
        global_config = self.root / "global.json"
        global_config.write_text("{}")
        self.environment = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("PLAYWRIGHT_", "PWTEST_"))
            and key not in ("NODE_OPTIONS", "NODE_PATH")
        }
        # Preserve only the reviewed wrapper's two inputs. In particular an
        # explicitly empty token remains empty for that wrapper to refuse.
        for key in ("PLAYWRIGHT_MCP_EXTENSION_TOKEN", "PLAYWRIGHT_MCP_EXECUTABLE_PATH"):
            if key in os.environ:
                self.environment[key] = os.environ[key]
        self.environment.update({
            "PWTEST_CLI_GLOBAL_CONFIG": str(global_config),
            "PLAYWRIGHT_DAEMON_SESSION_DIR": str(self.root / "daemon"),
            "TMPDIR": str(self.root / "tmp"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
        })
        self.configuration = self.root / "cli.json"
        output = (self.root / "output").resolve()
        if not output.is_relative_to(self.root.resolve()):
            raise PhaseFailure("ArtifactSetup")
        self.configuration.write_text(json.dumps({
            "outputDir": str(output),
            "saveSession": False, "saveTrace": False, "saveVideo": False,
            "codegen": "none",
            "browser": {"initPage": [], "initScript": []},
            "timeouts": {"action": self.task["limits"]["action_ms"], "navigation": self.task["limits"]["navigation_ms"]},
        }))

    def cleanup(self, outcome):
        self.cleaning = True
        limit = self.task["limits"]["cleanup_ms"]
        try:
            if self.running and self.attached:
                # A best-effort connected close after a broken frontend. Its
                # result cannot upgrade an interrupted read to success: a
                # timed-out creation may still be in flight in the daemon.
                try:
                    self.invoke(["run-code", self.code("closeOwnedPage")], limit)
                except Exception:
                    pass
                outcome = refused("TabCleanup")
            if self.started and self.pidfds:
                try:
                    self.invoke(["detach"], limit)
                except Exception:
                    outcome = refused("SessionCleanup")
            self.adopt()
            for pid, descriptor in self.pidfds.items():
                try:
                    if not self.await_exit(descriptor, limit):
                        outcome = refused("SessionCleanup")
                        self.terminate(descriptor)
                    os.waitpid(pid, 0)
                except Exception:
                    outcome = refused("SessionCleanup")
        except Exception:
            outcome = refused("SessionCleanup")
        finally:
            for descriptor in self.pidfds.values():
                os.close(descriptor)
            if self.root is not None:
                try:
                    shutil.rmtree(self.root)
                except Exception:
                    outcome = refused("ArtifactCleanup")
        return outcome

    def run(self):
        outcome = refused("ArtifactSetup")
        # Kernel interface constants describe Linux, not runtime policy.
        if ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) != 0:
            return refused("SessionCleanup")
        old_handlers = {number: signal.signal(number, self.on_signal) for number in (signal.SIGTERM, signal.SIGINT)}
        try:
            self.root = Path(tempfile.mkdtemp(prefix="browser-read-"))
            self.setup()
            self.started = True
            outcome = refused("SessionAttach")
            attached = self.invoke(["attach", "--extension=chrome", "--config=" + str(self.configuration)], (self.deadline - time.monotonic()) * 1000)
            if attached.get("session") != self.session or type(attached.get("pid")) is not int or attached["pid"] not in self.pidfds:
                raise PhaseFailure("SessionCleanup")
            self.attached = True
            self.running = True
            outcome = refused("SessionRun")
            read = self.invoke(["run-code", self.code("readPage")], (self.deadline - time.monotonic()) * 1000)
            if not isinstance(read.get("result"), str):
                raise PhaseFailure("SessionRun")
            outcome = json.loads(read["result"])
            if not isinstance(outcome, dict) or outcome.get("phase") not in ("Read", "Refused"):
                raise PhaseFailure("SessionRun")
            # A fixed read function returned: its finally has run. A TabCleanup
            # refusal explicitly retains uncertainty and still triggers close.
            self.running = outcome == refused("TabCleanup")
        except Interrupted:
            outcome = refused("Interrupted")
        except PhaseFailure as failure:
            outcome = refused(failure.phase) if outcome.get("refusal") != "SessionAttach" else outcome
        except Exception:
            # Keep the phase already entered; exception strings can contain
            # provider output and never cross this boundary.
            if outcome.get("phase") == "Read":
                outcome = refused("SessionRun")
        finally:
            outcome = self.cleanup(outcome)
            for number, handler in old_handlers.items():
                signal.signal(number, handler)
        return outcome


def main():
    try:
        task = json.load(sys.stdin)
        address = urllib.parse.urlsplit(task["url"])
        if address.scheme not in ("http", "https") or not address.hostname or address.username is not None or address.password is not None or any(c.isspace() or ord(c) < 32 or c == "\\" for c in task["url"]):
            outcome = refused("InvalidRegistry")
        else:
            outcome = Session(sys.argv[1], task).run()
        encoded = json.dumps(outcome)
        if len(encoded.encode()) > task["limits"]["output_bytes"]:
            encoded = json.dumps(refused("SessionRun"))
        print(encoded)
    except BaseException:
        print(json.dumps(refused("BrowserOutcome")))


if __name__ == "__main__":
    main()
