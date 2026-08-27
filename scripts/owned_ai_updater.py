"""Small update primitives shared by Home's four owned AI packages.

This intentionally contains only the HTTP, JSON, Debian-index, and Nix hash
operations needed by the package update entrypoints.  It is not a copy of the
upstream agent updater framework, so unrelated package flows do not become a
new Home dependency.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import stat
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path
from typing import Any


USER_AGENT = "CriomOS-home owned AI package updater"
DUMMY_SHA256_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request) as response:
        return bytes(response.read())


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode()


def fetch_json(url: str) -> Any:
    return json.loads(fetch_text(url))


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def atomic_write_text(path: Path, content: str) -> None:
    """Replace a checked-out text file atomically, preserving its mode."""
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary:
            temporary_name = temporary.name
            os.fchmod(temporary.fileno(), mode)
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def save_json(path: Path, value: dict[str, Any]) -> None:
    """Replace a checked-out JSON file atomically, preserving its mode."""
    atomic_write_text(path, json.dumps(value, indent=2, sort_keys=True) + "\n")


def resolve_checkout_root(explicit: Path | None, package: str) -> Path:
    """Find and validate the mutable source checkout used by an updater."""
    root = (explicit or Path.cwd()).expanduser().resolve()
    if not (root / "flake.nix").is_file():
        raise RuntimeError(f"{root} is not a CriomOS-home checkout (missing flake.nix)")
    package_dir = root / "owned-agents" / package
    hashes_file = package_dir / "hashes.json"
    if not package_dir.is_dir() or not hashes_file.is_file():
        raise RuntimeError(f"{root} has no mutable owned-agents/{package}/hashes.json")
    return root


def hex_to_sri(value: str) -> str:
    digest = bytes.fromhex(value)
    return "sha256-" + base64.b64encode(digest).decode("ascii")


def sha256_sri(value: bytes) -> str:
    return "sha256-" + base64.b64encode(hashlib.sha256(value).digest()).decode("ascii")


def version_tuple(value: str) -> tuple[int, ...]:
    result = []
    for part in value.split("."):
        digits = "".join(character for character in part if character.isdigit())
        result.append(int(digits or "0"))
    return tuple(result)


def should_update(current: str, candidate: str) -> bool:
    return not current or version_tuple(candidate) > version_tuple(current)


def verify_key_fingerprint(gpg: str, key_file: Path, expected: str) -> None:
    """Require the explicitly trusted archive key before accepting signatures."""
    completed = subprocess.run(
        [gpg, "--batch", "--with-colons", "--show-keys", str(key_file)],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(f"unable to inspect archive key {key_file}:\n{completed.stderr}")
    fingerprints = {
        fields[9].upper()
        for line in completed.stdout.splitlines()
        if (fields := line.split(":")) and fields[0] == "fpr" and len(fields) > 9
    }
    if expected.upper() not in fingerprints:
        raise RuntimeError(
            f"archive key fingerprint changed (expected {expected}); explicit trust change required"
        )


def dearmor_key(gpg: str, key_file: Path, output: Path) -> None:
    subprocess.run(
        [gpg, "--batch", "--dearmor", "--output", str(output), str(key_file)],
        check=True,
        capture_output=True,
        text=True,
    )


def nix_path_hash(path: Path) -> str:
    completed = subprocess.run(
        ["nix", "hash", "path", "--type", "sha256", "--sri", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def url_hash(url: str, *, unpack: bool = False) -> str:
    """Calculate the same SRI hash consumed by the corresponding Nix fetcher."""
    payload = fetch_bytes(url)
    if not unpack:
        return sha256_sri(payload)

    with tempfile.TemporaryDirectory(prefix="criomos-home-update-") as directory:
        archive = Path(directory) / "source.tar.gz"
        unpacked = Path(directory) / "source"
        archive.write_bytes(payload)
        unpacked.mkdir()
        with tarfile.open(archive, mode="r:*") as tar:
            tar.extractall(unpacked, filter="data")
        entries = list(unpacked.iterdir())
        if len(entries) == 1 and entries[0].is_dir():
            return nix_path_hash(entries[0])
        return nix_path_hash(unpacked)


def update_dependency_hash(
    flake_attribute: str, dependency: str, hashes_file: Path, data: dict[str, Any]
) -> None:
    """Run the package's evaluation witness and persist the discovered hash."""
    original = hashes_file.read_text()
    try:
        # Nix discovers a dependency hash by evaluating a temporary dummy
        # value. Keep that probe private to this function; callers commit the
        # complete, validated update only after the probe succeeds.
        save_json(hashes_file, data)
        completed = subprocess.run(
            ["nix", "build", flake_attribute, "--no-link"],
            check=False,
            capture_output=True,
            text=True,
        )
        output = completed.stdout + completed.stderr
        marker = "got: sha256-"
        start = output.rfind(marker)
        if completed.returncode == 0:
            raise RuntimeError(f"unable to discover {dependency}: Nix accepted the probe hash")
        if start < 0:
            raise RuntimeError(f"unable to discover {dependency} from Nix build:\n{output}")
        end = start + len(marker)
        while end < len(output) and output[end] in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=":
            end += 1
        replacement = output[start:end]
        if replacement == marker:
            raise RuntimeError(f"unable to discover a valid {dependency} replacement")
        data[dependency] = replacement
    finally:
        # Restore the checked-in hash on every probe failure, including a Nix
        # failure that did not yield a valid replacement.
        atomic_write_text(hashes_file, original)
