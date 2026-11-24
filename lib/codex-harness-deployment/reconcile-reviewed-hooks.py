"""Reconcile reviewed hooks through the owning plain Codex app-server."""

import copy
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct
import sys
import tempfile
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


class Codex:
    def __init__(self, connection, timeout, home):
        self.connection = connection
        self.timeout = timeout
        self.number = 0
        result = self.request("initialize", {
            "clientInfo": {"name": "criomos-reviewed-hooks", "version": "1"},
        })
        require(result.get("codexHome") == str(home), "The peer reports another Codex home.")
        self.send({"method": "initialized"})

    def send(self, message):
        self.connection.send(json.dumps(message))

    def request(self, method, params):
        self.number += 1
        self.send({"id": self.number, "method": method, "params": params})
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
    return layer["version"]


def replace_hooks(path, previous, document):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            temporary.write((json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode())
            temporary.flush()
            os.fsync(temporary.fileno())
            exact_path(path, stat.S_ISREG, os.getuid(), 0o077)
            require(path.read_bytes() == previous, "The hook declarations changed during activation.")
            os.replace(pending, path)
        finally:
            pending.unlink(missing_ok=True)


def reconcile(plan):
    uid = os.getuid()
    home = Path(plan["home"])
    public_key = Path(plan["hostPublicKey"])
    exact_path(public_key, stat.S_ISREG, 0, 0o022)
    require(
        hashlib.sha256(public_key.read_bytes()).hexdigest() == plan["hostPublicKeyDigest"],
        "The approval belongs to a different host.",
    )
    exact_path(home, stat.S_ISDIR, uid, 0o077)
    marker = Path(plan["marker"])
    require(
        str(marker.resolve(strict=True)) == plan["hookTarget"],
        "Home did not install the reviewed immutable hook target.",
    )
    config_path, hooks_path = home / "config.toml", home / "hooks.json"
    control = Path(plan["socket"])
    exact_path(config_path, stat.S_ISREG, uid, 0o077)
    exact_path(hooks_path, stat.S_ISREG, uid, 0o077)
    exact_path(control.parent, stat.S_ISDIR, uid, 0o077)
    require(control.lstat().st_uid == uid, "The rendezvous is owned by a different user.")
    protected_socket = control.resolve(strict=True)
    exact_path(protected_socket.parent, stat.S_ISDIR, uid, 0o077)
    exact_path(protected_socket, stat.S_ISSOCK, uid, 0)
    config_bytes, hooks_bytes = config_path.read_bytes(), hooks_path.read_bytes()
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
        peer, peer_uid, _ = struct.unpack("3i", stream.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        require(
            peer_uid == uid and os.readlink(f"/proc/{peer}/exe") == plan["codex"],
            "The socket does not belong to the pinned plain Codex binary.",
        )
        with unix_connect(sock=stream, proxy=None, open_timeout=timeout, close_timeout=timeout) as connection:
            codex = Codex(connection, timeout, home)
            version = verify_user_layer(codex, config_path, state)
            verify_inventory(codex, home, hooks_path, before)
            exact_path(config_path, stat.S_ISREG, uid, 0o077)
            require(config_path.read_bytes() == config_bytes, "The user config changed during activation.")
            if candidate != current:
                replace_hooks(hooks_path, hooks_bytes, candidate)
            verify_inventory(codex, home, hooks_path, after)
            exact_path(config_path, stat.S_ISREG, uid, 0o077)
            require(config_path.read_bytes() == config_bytes, "The user config changed during approval.")
            edits = [
                {"keyPath": f"hooks.state.{json.dumps(key, ensure_ascii=False)}.trusted_hash",
                 "value": digest, "mergeStrategy": "upsert"}
                for key, digest in after.items()
                if state.get(key, {}).get("trusted_hash") != digest
            ]
            if edits:
                receipt = codex.request("config/batchWrite", {
                    "filePath": str(config_path),
                    "expectedVersion": version,
                    "reloadUserConfig": False,
                    "edits": edits,
                })
                require(
                    receipt.get("status") == "ok" and receipt.get("filePath") == str(config_path),
                    "Codex did not confirm the exact user-config write.",
                )
            approved_state = config.setdefault("hooks", {}).setdefault("state", {})
            for key, digest in after.items():
                approved_state.setdefault(key, {})["trusted_hash"] = digest
            exact_path(config_path, stat.S_ISREG, uid, 0o077)
            require(tomllib.loads(config_path.read_text()) == config, "The user config differs outside the reviewed changes.")
            verify_inventory(codex, home, hooks_path, after, target_status=True)


if __name__ == "__main__":
    try:
        reconcile(json.loads(Path(sys.argv[1]).read_text()))
    except Refusal as error:
        sys.exit(f"Codex hook approval: {error}")
    except Exception as error:
        sys.exit(f"Codex hook approval could not verify its inputs or reply ({type(error).__name__}).")
