"""Shared scope and read-only evidence for the reviewed plain Codex transition."""

from contextlib import contextmanager
import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct
import time
import tomllib

from websockets.sync.client import unix_connect


class Refusal(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise Refusal(reason)


def exact_path(path, kind, owner, forbidden_permissions):
    metadata = path.lstat()
    require(
        path.resolve(strict=True) == path
        and kind(metadata.st_mode)
        and metadata.st_uid == owner
        and not metadata.st_mode & forbidden_permissions,
        f"Unexpected ownership, permissions or type: {path.name}.",
    )


class ReadOnlyCodex:
    methods = frozenset({"initialize", "config/read", "hooks/list"})

    def __init__(self, connection, timeout, home):
        self.connection = connection
        self.timeout = timeout
        self.number = 0
        result = self.request("initialize", {
            "clientInfo": {"name": "criomos-reviewed-hooks", "version": "1"},
        })
        require(result.get("codexHome") == str(home), "The peer reports another Codex home.")
        self.connection.send(json.dumps({"method": "initialized"}))

    def request(self, method, params):
        require(method in self.methods, "The RPC is outside the declared capability.")
        self.number += 1
        self.connection.send(json.dumps({"id": self.number, "method": method, "params": params}))
        deadline = time.monotonic() + self.timeout
        while True:
            reply = json.loads(self.connection.recv(timeout=max(0, deadline - time.monotonic())))
            if reply.get("id") == self.number:
                require("result" in reply, f"Codex refused {method}.")
                return reply["result"]


def candidate_document(document, plan, hooks_path):
    current = copy.deepcopy(document)
    events = current["hooks"]
    commands = plan["commands"]
    target = plan["target"]
    expected = {}
    for event, digest in plan["handlers"].items():
        groups = events[event]
        group = groups[0]
        allowed = {
            side: {"type": "command", "command": command, "timeout": plan["hookTimeout"]}
            for side, command in commands.items()
        }
        present = [side for side, handler in allowed.items() if group["hooks"][0] == handler]
        require(
            set(group) == {"hooks"} and len(present) == 1,
            f"The reviewed declaration for {event} is missing or changed.",
        )
        matching = sum(
            handler.get("type") == "command" and handler.get("command") in commands.values()
            for entry in groups for handler in entry["hooks"]
        )
        require(matching == 1, f"The reviewed declaration for {event} is ambiguous.")
        group["hooks"][0] = allowed[target]
        key = f'{hooks_path}:{digest["event"]}:0:0'
        expected[key] = (digest[present[0]], digest[target])
    return current, expected


def verify_inventory(codex, home, hooks_path, hashes, target_status=False):
    inventories = codex.request("hooks/list", {"cwds": [str(home)]})["data"]
    require(len(inventories) == 1, "Codex returned an unexpected hook inventory.")
    handlers = inventories[0]["hooks"]
    for key, digest in hashes.items():
        rows = [handler for handler in handlers if handler["key"] == key]
        require(
            len(rows) == 1
            and rows[0]["sourcePath"] == str(hooks_path)
            and rows[0]["currentHash"] == digest
            and not rows[0]["isManaged"],
            "The pinned declaration fingerprint or owner differs from its review.",
        )
        if target_status:
            require(rows[0]["trustStatus"] == "trusted", "An approved declaration did not read back as trusted.")


def verify_user_layer(codex, config_path, disk_state):
    response = codex.request("config/read", {"includeLayers": True})
    layers = [layer for layer in response["layers"] if layer["name"]["type"] == "user"]
    require(
        len(layers) == 1
        and layers[0]["name"] == {"type": "user", "file": str(config_path), "profile": None},
        "Codex did not expose exactly the intended unprofiled user layer.",
    )
    layer = layers[0]
    require(
        layer["config"].get("hooks", {}).get("state", {}) == disk_state,
        "The Codex user-layer hook state differs from its file.",
    )
    require(layer["config"].get("features", {}).get("hooks") is True, "The user layer does not enable hooks.")
    require(isinstance(layer["version"], str) and layer["version"], "Codex did not report a user-layer version.")
    return layer["version"]


def digest(content):
    return hashlib.sha256(content).hexdigest()


def peer_identity(stream, expected_executable):
    pid, uid, _ = struct.unpack("3i", stream.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    require(pid > 0 and uid == os.getuid(), "The peer is not in the owning user identity.")
    process = Path("/proc") / str(pid)
    executable = os.readlink(process / "exe")
    require(executable == expected_executable, "The socket does not belong to the pinned plain Codex binary.")
    start_time = (process / "stat").read_text().rsplit(")", 1)[1].split()[19]
    return {
        "pid": pid,
        "uid": uid,
        "startTime": start_time,
        "executable": executable,
        "bootId": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
    }


def read_owned_file(path):
    exact_path(path, stat.S_ISREG, os.getuid(), 0o077)
    return path.read_bytes()


@contextmanager
def observe(plan_path, codex_type=ReadOnlyCodex):
    plan_bytes = plan_path.read_bytes()
    plan = json.loads(plan_bytes)
    uid = os.getuid()
    home = Path(plan["home"])
    public_key = Path(plan["hostPublicKey"])
    exact_path(public_key, stat.S_ISREG, 0, 0o022)
    require(digest(public_key.read_bytes()) == plan["hostPublicKeyDigest"], "The approval belongs to a different host.")
    exact_path(home, stat.S_ISDIR, uid, 0o077)
    require(
        str(Path(plan["marker"]).resolve(strict=True)) == plan["hookTarget"],
        "Home did not install the reviewed immutable hook target.",
    )
    config_path, hooks_path = home / "config.toml", home / "hooks.json"
    control = Path(plan["socket"])
    exact_path(control.parent, stat.S_ISDIR, uid, 0o077)
    require(control.lstat().st_uid == uid, "The rendezvous is owned by a different user.")
    protected_socket = control.resolve(strict=True)
    exact_path(protected_socket.parent, stat.S_ISDIR, uid, 0o077)
    exact_path(protected_socket, stat.S_ISSOCK, uid, 0o077)
    config_bytes, hooks_bytes = read_owned_file(config_path), read_owned_file(hooks_path)
    config = tomllib.loads(config_bytes.decode())
    state = config.get("hooks", {}).get("state", {})
    require(
        not any("/" in (entry.get("trusted_hash") or "") for entry in state.values()),
        "A combined plugin approval would be rewritten by this Codex release.",
    )
    current = json.loads(hooks_bytes)
    candidate, expected = candidate_document(current, plan, hooks_path)
    for key, digests in expected.items():
        require(
            state.get(key, {}).get("trusted_hash") in {None, *digests},
            "An existing approval disagrees with the reviewed transition.",
        )
    before = {key: source for key, (source, _) in expected.items()}
    after = {key: destination for key, (_, destination) in expected.items()}
    timeout = plan["requestTimeout"]
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
        stream.settimeout(timeout)
        stream.connect(str(protected_socket))
        peer = peer_identity(stream, plan["codex"])
        with unix_connect(sock=stream, proxy=None, open_timeout=timeout, close_timeout=timeout) as connection:
            codex = codex_type(connection, timeout, home)
            version = verify_user_layer(codex, config_path, state)
            verify_inventory(codex, home, hooks_path, before)
            evidence = {
                "planDigest": digest(plan_bytes),
                "peer": peer,
                "userLayer": {"file": str(config_path), "profile": None, "version": version},
                "configDigest": digest(config_bytes),
                "hooksDigest": digest(hooks_bytes),
            }

            def revalidate():
                require(
                    control.resolve(strict=True) == protected_socket
                    and peer_identity(connection.socket, plan["codex"]) == peer,
                    "The owning app-server identity changed during approval.",
                )
                require(
                    read_owned_file(config_path) == config_bytes and read_owned_file(hooks_path) == hooks_bytes,
                    "The predecessor hook files changed during approval.",
                )

            revalidate()
            yield codex, evidence, revalidate, (config_path, hooks_path, config, hooks_bytes, state, current, candidate, after)
