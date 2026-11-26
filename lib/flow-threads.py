#!/usr/bin/env python3
"""A one-shot, passive Flow activity directory."""
from collections import Counter
import concurrent.futures
import dataclasses
import json
import os
from pathlib import Path
import re
import select
import socket
import stat
import struct
import subprocess
import sys
import time
import uuid

MAX_FRAME = 1024 * 1024
MAX_THREADS = 32
CLIENTS = Path.home() / ".local/bin"
ASPECTS = {"Psyche", "Mind", "Field"}
MODELS = {"Fable", "Opus", "Sonnet", "Haiku", "Astra", "Sol", "Luna", "Terra"}
HEAD = re.compile(r"([A-Z][A-Za-z0-9]*)\.")


class Unavailable(ValueError):
    """A source cannot establish the fact being read."""


@dataclasses.dataclass(frozen=True)
class Variant:
    name: str
    value: object


class Datom:
    """Read the text carried by these two current Signal opening frames."""

    def __init__(self, text):
        self.text = text
        self.at = 0

    def whitespace(self):
        while self.at < len(self.text) and self.text[self.at].isspace():
            self.at += 1

    def node(self, depth=0):
        self.whitespace()
        if depth > 128 or self.at == len(self.text):
            raise Unavailable("incomplete Datom or nesting limit")
        start = self.at
        glyph = self.text[start]
        if glyph in "{[":
            close = "}" if glyph == "{" else "]"
            self.at += 1
            values = []
            while True:
                self.whitespace()
                if self.at == len(self.text):
                    raise Unavailable("unclosed Datom container")
                if self.text[self.at] == close:
                    self.at += 1
                    return tuple(values) if glyph == "{" else values
                values.append(self.node(depth + 1))
        if glyph == "«":
            self.at += 1
            nest, parts = 1, []
            while self.at < len(self.text):
                current = self.text[self.at]
                self.at += 1
                if current == "\\" and self.text[self.at:self.at + 1] in {"«", "»", "\\"}:
                    current = self.text[self.at]
                    self.at += 1
                elif current == "«":
                    nest += 1
                elif current == "»":
                    nest -= 1
                    if not nest:
                        return "".join(parts)
                parts.append(current)
            raise Unavailable("unclosed Datom string")
        head = HEAD.match(self.text, start)
        if head:
            self.at = head.end()
            return Variant(head[1], self.node(depth + 1))
        while self.at < len(self.text):
            glyph = self.text[self.at]
            if glyph.isspace() or glyph in "{}[]«»":
                break
            self.at += 1
        if self.at == start:
            raise Unavailable("unexpected Datom delimiter")
        return self.text[start:self.at]

    def opening(self, name):
        result = self.node()
        self.whitespace()
        if self.at != len(self.text) or not isinstance(result, Variant) or result.name != name:
            raise Unavailable(f"expected {name} opening frame")
        return result.value


def observer_frame(binary, query):
    """Read the single opening reply; close only our own subscription."""
    with subprocess.Popen([CLIENTS / binary, query], stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL) as child:
        deadline = time.monotonic() + 5
        data = bytearray()
        try:
            while len(data) < MAX_FRAME:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([child.stdout], [], [], remaining)[0]:
                    break
                part = os.read(child.stdout.fileno(), min(MAX_FRAME - len(data), 65536))
                if not part:
                    break
                data.extend(part)
                # On this CLI the outer reply is compacted onto one line;
                # quoted newlines, if literal, must not truncate the reply.
                for end in (index for index, byte in enumerate(data) if byte == 10):
                    try:
                        text = bytes(data[:end]).decode("utf-8")
                        line = Datom(text)
                        line.node()
                        line.whitespace()
                        if line.at == len(text):
                            return text
                    except (Unavailable, UnicodeError):
                        continue
            raise Unavailable(f"{query} opening frame missing or malformed")
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


def address(value):
    if (not isinstance(value, tuple) or len(value) != 3
            or any(not isinstance(item, str) for item in value)
            or value[0] not in ASPECTS or value[2] not in MODELS
            or not re.fullmatch(r"[a-z][A-Za-z0-9]*", value[1])):
        raise Unavailable("invalid declared address")
    return " ".join(value)


@dataclasses.dataclass(frozen=True)
class Configuration:
    purposes: dict
    flows_root: Path
    session: str
    endpoints: tuple


def configuration(text):
    data = Datom(text).opening("Configuration")
    if not isinstance(data, tuple) or len(data) != 23:
        raise Unavailable("unexpected Configuration shape")
    nexus, declarations = data[0], data[8]
    if not isinstance(nexus, tuple) or len(nexus) != 11 or not isinstance(declarations, list):
        raise Unavailable("unexpected Nexus or declaration shape")
    paths = []
    for endpoint in nexus[1:3]:
        if not isinstance(endpoint, tuple) or len(endpoint) != 4 or not isinstance(endpoint[2], str):
            raise Unavailable("unexpected Codex endpoint shape")
        if endpoint[2] and Path(endpoint[2]).is_absolute() and endpoint[2] not in paths:
            paths.append(endpoint[2])
    purposes = {}
    for row in declarations:
        if not isinstance(row, tuple) or len(row) != 12 or not isinstance(row[9], str):
            raise Unavailable("invalid declaration row")
        name = address(row[0])
        if name in purposes:
            raise Unavailable("duplicate declaration address")
        purposes[name] = row[9]
    if not isinstance(nexus[0], str) or not Path(nexus[0]).is_absolute() or not isinstance(nexus[10], str):
        raise Unavailable("missing source root or Herdr session")
    return Configuration(purposes, Path(nexus[0]) / "flows", nexus[10], tuple(paths))


def receiving(text):
    rows = Datom(text).opening("MetaflowsObserved")
    if not isinstance(rows, list):
        raise Unavailable("invalid MetaflowsObserved shape")
    observed = {}
    for row in rows:
        if not isinstance(row, tuple) or len(row) != 4:
            raise Unavailable("invalid metaflow row")
        name, state = address(row[0]), row[1]
        if name in observed:
            raise Unavailable("duplicate observed address")
        if state == "Asleep":
            observed[name] = None
        elif (isinstance(state, Variant) and state.name == "Awake"
              and isinstance(state.value, str) and re.fullmatch(r"[a-f0-9]{6,32}", state.value)):
            observed[name] = state.value
        else:
            raise Unavailable("invalid observed receiving state")
    return observed


def native_claim(root, alias):
    """Read a current receiving Flow ID's own, owner-controlled identity claim."""
    try:
        path = root / f".{alias}.flow-id"
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 512:
                return None
            lines = stream.read(513).decode("ascii").splitlines()
        if len(lines) not in {4, 5} or lines[0] != "version=1" or lines[3] != f"alias={alias}":
            return None
        harness = lines[1].removeprefix("harness=")
        identity = lines[2].removeprefix("identity=")
        if (lines[1] not in {"harness=codex", "harness=claude"}
                or not lines[2].startswith("identity=")
                or not re.fullmatch(r"[a-f0-9]{32}", identity)):
            return None
        if harness == "codex" and len(lines) != 4:
            return None
        if harness == "claude" and (uuid.UUID(identity).variant != uuid.RFC_4122
                                  or lines[4:] not in [[], ["uuid-version=uuid-v4"], ["uuid-version=uuid-v5"]]
                                  or uuid.UUID(identity).version != (5 if lines[4:] == ["uuid-version=uuid-v5"] else 4)):
            return None
        return harness, str(uuid.UUID(identity))
    except (OSError, ValueError):
        return None


@dataclasses.dataclass(frozen=True)
class Thread:
    state: str
    parent: str | None
    parent_known: bool


@dataclasses.dataclass(frozen=True)
class Native:
    threads: dict
    terminals: dict
    complete: bool


class CodexRead:
    """Only a bounded owner-local WebSocket and read-only app-server methods."""

    def __init__(self, peer):
        self.peer = peer
        self.serial = 0
        self.deadline = time.monotonic() + 5

    def call(self, method, params):
        if method not in {"initialize", "thread/loaded/list", "thread/read", "thread/backgroundTerminals/list"}:
            raise Unavailable("unsupported Codex read")
        self.serial += 1
        self.peer.send(json.dumps({"id": self.serial, "method": method, "params": params}))
        while (remaining := self.deadline - time.monotonic()) > 0:
            reply = json.loads(self.peer.recv(timeout=remaining))
            if isinstance(reply, dict) and reply.get("id") == self.serial:
                if not isinstance(reply.get("result"), dict):
                    raise Unavailable(f"Codex refused {method}")
                return reply["result"]
        raise Unavailable("Codex read timed out")

    def list_loaded(self):
        page = self.call("thread/loaded/list", {"limit": MAX_THREADS})
        ids = page.get("data")
        if (not isinstance(ids, list) or len(ids) > MAX_THREADS
                or any(not isinstance(item, str) for item in ids) or len(set(ids)) != len(ids)):
            raise Unavailable("invalid loaded thread list")
        return ids, "nextCursor" in page and page["nextCursor"] is None

    def read_thread(self, native_id):
        thread = self.call("thread/read", {"threadId": native_id, "includeTurns": False}).get("thread")
        if not isinstance(thread, dict) or thread.get("id") != native_id or not isinstance(thread.get("status"), dict):
            raise Unavailable("thread identity or runtime status missing")
        state = thread["status"].get("type")
        source = thread.get("source")
        if isinstance(source, str) and source in {"cli", "vscode", "exec", "appServer"}:
            return Thread(state, None, True)
        if isinstance(source, dict) and isinstance(source.get("subAgent"), dict):
            spawn = source["subAgent"].get("thread_spawn")
            if isinstance(spawn, dict) and isinstance(spawn.get("parent_thread_id"), str):
                return Thread(state, spawn["parent_thread_id"], True)
        return Thread(state, None, False)

    def read_terminals(self, native_id):
        page = self.call("thread/backgroundTerminals/list", {"threadId": native_id, "limit": MAX_THREADS})
        rows = page.get("data")
        if not isinstance(rows, list):
            return None
        if any(isinstance(row, dict) and isinstance(row.get("processId"), str)
               and row["processId"] for row in rows):
            return True
        return False if not rows and "nextCursor" in page and page["nextCursor"] is None else None

    def snapshot(self, roots):
        self.call("initialize", {"clientInfo": {"name": "flow-threads", "version": "1"},
                                "capabilities": {"experimentalApi": True}})
        self.peer.send(json.dumps({"method": "initialized", "params": None}))
        ids, complete = self.list_loaded()
        threads = {}
        for native_id in ids:
            try:
                threads[native_id] = self.read_thread(native_id)
            except (Unavailable, OSError, TimeoutError, ValueError):
                complete = False
        needed = set().union(*(family(threads, root) for root in roots if root in threads))
        terminals = {}
        for native_id in sorted(needed):
            if threads[native_id].state == "active":
                continue
            try:
                terminals[native_id] = self.read_terminals(native_id)
            except (Unavailable, OSError, TimeoutError, ValueError):
                complete = False
        if complete:
            final_ids, final_complete = self.list_loaded()
            complete = final_complete and set(final_ids) == set(ids)
        complete = complete and all(
            row.parent_known and (row.parent is None or row.parent in threads)
            for row in threads.values()
        )
        return Native(threads, terminals, complete)


def read_codex(endpoint, roots):
    try:
        from websockets.exceptions import WebSocketException
        from websockets.sync.client import unix_connect
    except ImportError:
        return None
    try:
        link = os.lstat(endpoint)
        target = Path(endpoint).resolve(strict=True)
        before = target.stat()
        if link.st_uid != os.getuid() or before.st_uid != os.getuid() or not stat.S_ISSOCK(before.st_mode):
            return None
        with unix_connect(str(target), open_timeout=2, close_timeout=1, max_size=MAX_FRAME) as peer:
            _, uid, _ = struct.unpack("3i", peer.socket.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            if uid != os.getuid():
                return None
            snapshot = CodexRead(peer).snapshot(roots)
        after = target.stat()
        if (Path(endpoint).resolve(strict=True) == target
                and (before.st_dev, before.st_ino) == (after.st_dev, after.st_ino)):
            return snapshot
    except (OSError, ValueError, TimeoutError, WebSocketException):
        pass
    return None


def family(threads, root):
    """Reach known descendants; cycle-bounded even with malformed metadata."""
    found = {root}
    while True:
        expanded = found | {name for name, row in threads.items()
                            if row.parent_known and row.parent in found}
        if expanded == found:
            return found
        found = expanded


def codex_activity(native_id, snapshots):
    matches = [snapshot for snapshot in snapshots if snapshot and native_id in snapshot.threads]
    if len(matches) != 1:
        return "unknown"
    native = matches[0]
    scope = family(native.threads, native_id)
    if any(native.threads[item].state == "active" or native.terminals.get(item) is True for item in scope):
        return "acting"
    if (all(snapshot is not None and snapshot.complete for snapshot in snapshots)
            and all(native.threads[item].state == "idle"
                    and native.terminals.get(item) is False for item in scope)):
        return "resting"
    return "unknown"


def claude_agents(session):
    try:
        answer = subprocess.run([CLIENTS / "herdr", "--session", session, "agent", "list"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                timeout=3, check=True)
        if len(answer.stdout) > MAX_FRAME:
            return []
        result = json.loads(answer.stdout)["result"]
        return result["agents"] if result["type"] == "agent_list" and isinstance(result["agents"], list) else []
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return []


def claude_activity(native_id, agents):
    exact = [agent for agent in agents if isinstance(agent, dict) and agent.get("agent") == "claude"
             and isinstance(agent.get("agent_session"), dict)
             and agent["agent_session"].get("agent") == "claude"
             and agent["agent_session"].get("kind") == "id"
             and agent["agent_session"].get("value") == native_id and agent.get("terminal_id")]
    # A Herdr idle pane does not prove its Claude work or children ended.
    return "acting" if len(exact) == 1 and exact[0].get("agent_status") == "working" else "unknown"


def directory(purposes, states, claims, snapshots, agents):
    for name, purpose in sorted(purposes.items()):
        if states is not None and name in states and states[name] is None:
            activity = "asleep"
        else:
            claim = claims.get(name)
            activity = ("unknown" if not claim else codex_activity(claim[1], snapshots)
                        if claim[0] == "codex" else claude_activity(claim[1], agents))
        yield name, activity, purpose


def one_line(text):
    return "".join(glyph if glyph.isprintable() or glyph == " " else ascii(glyph)[1:-1] for glyph in text)


def main():
    if len(sys.argv) != 1:
        print("usage: flow-threads", file=sys.stderr)
        return 2
    try:
        conf = configuration(observer_frame("flow-meta", "ObserveConfiguration"))
    except (OSError, ValueError) as error:
        print(f"flow-threads: declarations unavailable: {error}", file=sys.stderr)
        return 1
    try:
        states = receiving(observer_frame("flow", "Observe.Metaflows"))
    except (OSError, ValueError):
        print("flow-threads: receiving state unavailable; activity is unknown", file=sys.stderr)
        states = None
    aliases = Counter(alias for alias in (states or {}).values() if alias)
    claims = {name: native_claim(conf.flows_root, alias)
              for name, alias in (states or {}).items()
              if name in conf.purposes and alias and aliases[alias] == 1}
    roots = {claim[1] for claim in claims.values() if claim and claim[0] == "codex"}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as readers:
        providers = [readers.submit(read_codex, endpoint, roots) for endpoint in conf.endpoints] if roots else []
        seen_claude = any(claim and claim[0] == "claude" for claim in claims.values())
        claude = readers.submit(claude_agents, conf.session) if seen_claude else None
        snapshots = [provider.result() for provider in providers]
        agents = claude.result() if claude else []
    for name, activity, purpose in directory(conf.purposes, states, claims, snapshots, agents):
        print(f"{name} — {activity} — {one_line(purpose) if purpose else '(no purpose)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
