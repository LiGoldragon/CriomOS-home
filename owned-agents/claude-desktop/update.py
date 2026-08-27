#!/usr/bin/env python3
"""Refresh Claude Desktop from Anthropic's Debian package indexes."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path
from pathlib import PurePosixPath

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

from owned_ai_updater import (  # noqa: E402
    dearmor_key,
    fetch_bytes,
    hex_to_sri,
    load_json,
    resolve_checkout_root,
    save_json,
    should_update,
    verify_key_fingerprint,
    version_tuple,
)


APT_BASE = "https://downloads.claude.ai/claude-desktop/apt/stable"
KEY_FINGERPRINT = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
PLATFORMS = {"x86_64-linux": "amd64", "aarch64-linux": "arm64"}


def release_sha256(release: str, wanted_path: str) -> tuple[str, int]:
    in_sha256 = False
    for line in release.splitlines():
        if line == "SHA256:":
            in_sha256 = True
            continue
        if in_sha256 and not line.startswith(" "):
            break
        if in_sha256:
            digest, size, path = line.split()
            if path == wanted_path:
                return digest, int(size)
    raise ValueError(f"{wanted_path} missing from signed Release SHA256 section")


def verify_index(index: bytes, expected_hash: str, expected_size: int, architecture: str) -> None:
    if len(index) != expected_size:
        raise ValueError(
            f"Claude Desktop Packages size mismatch for {architecture}: "
            f"expected {expected_size}, got {len(index)}"
        )
    actual_hash = hashlib.sha256(index).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError(
            f"Claude Desktop Packages SHA256 mismatch for {architecture}: "
            f"expected {expected_hash}, got {actual_hash}"
        )


def verified_fingerprints(output: str) -> set[str]:
    return {
        fields[2].upper()
        for line in output.splitlines()
        if (fields := line.split())[:2] == ["[GNUPG:]", "VALIDSIG"] and len(fields) > 2
    }


def verify_repository(gpg: str, gpgv: str, key_file: Path) -> str:
    """Verify both the clear-signed and detached official APT metadata."""
    with tempfile.TemporaryDirectory(prefix="claude-desktop-updater-") as directory:
        root = Path(directory)
        keyring = root / "anthropic-archive-key.gpg"
        inrelease_file = root / "InRelease"
        release_from_inrelease = root / "Release.from-inrelease"
        release_file = root / "Release"
        release_signature = root / "Release.gpg"

        verify_key_fingerprint(gpg, key_file, KEY_FINGERPRINT)
        dearmor_key(gpg, key_file, keyring)
        inrelease = fetch_bytes(f"{APT_BASE}/dists/stable/InRelease")
        inrelease_file.write_bytes(inrelease)
        inrelease_verification = subprocess.run(
            [
                gpgv,
                "--keyring",
                str(keyring),
                "--status-fd",
                "1",
                "--output",
                str(release_from_inrelease),
                str(inrelease_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if inrelease_verification.returncode != 0:
            raise RuntimeError(
                "Claude Desktop InRelease signature verification failed:\n"
                f"{inrelease_verification.stderr}"
            )
        if KEY_FINGERPRINT not in verified_fingerprints(inrelease_verification.stdout):
            raise RuntimeError(
                "Claude Desktop InRelease signer changed; explicit trust change required"
            )

        release = fetch_bytes(f"{APT_BASE}/dists/stable/Release")
        release_signature_bytes = fetch_bytes(f"{APT_BASE}/dists/stable/Release.gpg")
        release_file.write_bytes(release)
        release_signature.write_bytes(release_signature_bytes)
        release_verification = subprocess.run(
            [
                gpgv,
                "--keyring",
                str(keyring),
                "--status-fd",
                "1",
                str(release_signature),
                str(release_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if release_verification.returncode != 0:
            raise RuntimeError(
                "Claude Desktop Release signature verification failed:\n"
                f"{release_verification.stderr}"
            )
        if KEY_FINGERPRINT not in verified_fingerprints(release_verification.stdout):
            raise RuntimeError(
                "Claude Desktop Release signer changed; explicit trust change required"
            )
        if release_from_inrelease.read_bytes() != release:
            raise ValueError("Claude Desktop InRelease and Release contents differ")
        return release.decode()


def latest_for_arch(architecture: str, release: str) -> tuple[str, str, str]:
    index_path = f"main/binary-{architecture}/Packages"
    expected_hash, expected_size = release_sha256(release, index_path)
    index = fetch_bytes(f"{APT_BASE}/dists/stable/{index_path}")
    verify_index(index, expected_hash, expected_size, architecture)
    candidates = []
    for paragraph in index.decode().split("\n\n"):
        fields = {}
        for line in paragraph.splitlines():
            if ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value
        if all(field in fields for field in ("Version", "Filename", "SHA256")):
            version = fields["Version"]
            filename = fields["Filename"]
            path = PurePosixPath(filename)
            expected_name = f"claude-desktop_{version}_{architecture}.deb"
            if (
                not filename.startswith("pool/")
                or path.is_absolute()
                or str(path) != filename
                or any(part in ("", ".", "..") for part in path.parts)
                or path.parts[:4] != ("pool", "main", "c", "claude-desktop")
                or path.name != expected_name
            ):
                raise ValueError(f"unsafe or unexpected Claude Desktop filename: {filename}")
            candidates.append((version, filename, fields["SHA256"]))
    if not candidates:
        raise RuntimeError(f"No Claude Desktop package stanza found for {architecture}")
    candidates.sort(key=lambda item: version_tuple(item[0]))
    return candidates[-1]


def verify_deb(filename: str, expected_hash: str) -> None:
    payload = fetch_bytes(f"{APT_BASE}/{filename}")
    actual_hash = hashlib.sha256(payload).hexdigest()
    if actual_hash != expected_hash.lower():
        raise ValueError(
            f"Claude Desktop .deb SHA256 mismatch for {filename}: "
            f"expected {expected_hash}, got {actual_hash}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--show-current", action="store_true", help="print the pinned version without network access"
    )
    parser.add_argument(
        "--root", type=Path, help="CriomOS-home checkout to update (default: current directory)"
    )
    parser.add_argument("--gpg", default="gpg", help="gpg executable (default: PATH lookup)")
    parser.add_argument("--gpgv", default="gpgv", help="gpgv executable (default: PATH lookup)")
    parser.add_argument("--key", type=Path, help="archive key (default: checkout copy)")
    args = parser.parse_args()
    root = resolve_checkout_root(args.root, "claude-desktop")
    hashes_file = root / "owned-agents" / "claude-desktop" / "hashes.json"
    key_file = (args.key or root / "owned-agents" / "claude-desktop" / "anthropic-archive-key.asc").resolve()
    current = load_json(hashes_file)
    verify_key_fingerprint(args.gpg, key_file, KEY_FINGERPRINT)
    if args.show_current:
        print(current["version"])
        return

    release = verify_repository(args.gpg, args.gpgv, key_file)
    urls = {}
    hashes = {}
    versions = {}
    for platform, architecture in PLATFORMS.items():
        version, filename, digest = latest_for_arch(architecture, release)
        verify_deb(filename, digest)
        versions[platform] = version
        urls[platform] = f"{APT_BASE}/{filename}"
        hashes[platform] = hex_to_sri(digest)
    if len(set(versions.values())) != 1:
        raise ValueError(f"Claude Desktop architecture versions differ: {sorted(versions.values())}")
    version = versions["x86_64-linux"]
    if current.get("version") and version_tuple(version) < version_tuple(current["version"]):
        raise ValueError(f"refusing to downgrade Claude Desktop from {current['version']} to {version}")
    if current.get("version") and not should_update(current["version"], version):
        if urls == current.get("urls") and hashes == current.get("hashes"):
            print("claude-desktop: already up to date")
            return
    save_json(hashes_file, {"version": version, "urls": urls, "hashes": hashes})
    print(f"claude-desktop: updated to {version}")


if __name__ == "__main__":
    main()
