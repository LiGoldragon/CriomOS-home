#!/usr/bin/env python3
"""Refresh ChatGPT from OpenAI's signed Debian repository."""

from __future__ import annotations

import argparse
import hashlib
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

from owned_ai_updater import (  # noqa: E402
    fetch_bytes,
    dearmor_key,
    hex_to_sri,
    load_json,
    resolve_checkout_root,
    save_json,
    should_update,
    verify_key_fingerprint,
)


KEY_FINGERPRINT = "3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4"
REPO_BASE = "https://persistent.oaistatic.com/codex-app-prod/linux/deb"
PLATFORMS = {"aarch64-linux": "arm64", "x86_64-linux": "amd64"}


def fetch(path: str) -> bytes:
    return fetch_bytes(f"{REPO_BASE}/{path}")


def signed_release(inrelease: bytes, key_file: Path, gpg: str, gpgv: str) -> str:
    """Verify OpenAI's signed InRelease using the pinned archive key."""
    with tempfile.TemporaryDirectory(prefix="chatgpt-updater-") as directory:
        root = Path(directory)
        inrelease_file = root / "InRelease"
        release_file = root / "Release"
        keyring_file = root / "openai-archive-key.gpg"
        inrelease_file.write_bytes(inrelease)
        dearmor_key(gpg, key_file, keyring_file)
        verification = subprocess.run(
            [
                gpgv,
                "--keyring",
                str(keyring_file),
                "--status-fd",
                "1",
                "--output",
                str(release_file),
                str(inrelease_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if verification.returncode != 0:
            raise RuntimeError(f"OpenAI InRelease signature verification failed:\n{verification.stderr}")
        fingerprints = {
            fields[2]
            for line in verification.stdout.splitlines()
            if (fields := line.split())[:2] == ["[GNUPG:]", "VALIDSIG"]
        }
        if KEY_FINGERPRINT not in fingerprints:
            raise RuntimeError("OpenAI InRelease was not signed by the pinned key")
        return release_file.read_text()


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
    raise ValueError(f"{wanted_path} missing from signed InRelease SHA256 section")


def verify_index(index: bytes, expected_hash: str, expected_size: int) -> None:
    if len(index) != expected_size:
        raise ValueError(f"Packages size mismatch: expected {expected_size}, got {len(index)}")
    actual_hash = hashlib.sha256(index).hexdigest()
    if actual_hash != expected_hash:
        raise ValueError(f"Packages SHA256 mismatch: expected {expected_hash}, got {actual_hash}")


def parse_packages(packages: str) -> list[dict[str, str]]:
    records = []
    for paragraph in packages.strip().split("\n\n"):
        record = {}
        for line in paragraph.splitlines():
            if line.startswith((" ", "\t")):
                continue
            key, separator, value = line.partition(":")
            if separator:
                record[key] = value.strip()
        records.append(record)
    return records


def source(platform: str, architecture: str, release: str) -> dict[str, str]:
    index_path = f"main/binary-{architecture}/Packages"
    expected_hash, expected_size = release_sha256(release, index_path)
    index = fetch(f"dists/stable/{index_path}")
    verify_index(index, expected_hash, expected_size)
    record = next(
        (
            candidate
            for candidate in parse_packages(index.decode())
            if candidate.get("Package") == "chatgpt"
            and candidate.get("Architecture") == architecture
        ),
        None,
    )
    if record is None:
        raise ValueError(f"chatgpt ({architecture}) missing from {index_path}")
    missing = [field for field in ("Version", "Filename", "SHA256") if field not in record]
    if missing:
        raise ValueError(f"chatgpt ({architecture}) missing fields: {', '.join(missing)}")
    filename = record["Filename"]
    if not filename.startswith("pool/") or ".." in Path(filename).parts:
        raise ValueError(f"unsafe package filename in signed index: {filename}")
    return {
        "version": record["Version"],
        "url": f"{REPO_BASE}/{filename}",
        "hash": hex_to_sri(record["SHA256"]),
    }


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
    root = resolve_checkout_root(args.root, "chatgpt")
    package_dir = root / "owned-agents" / "chatgpt"
    hashes_file = package_dir / "hashes.json"
    key_file = (args.key or package_dir / "openai-archive-key.asc").resolve()
    current = load_json(hashes_file)
    verify_key_fingerprint(args.gpg, key_file, KEY_FINGERPRINT)
    if args.show_current:
        versions = {source["version"] for source in current["sources"].values()}
        print(next(iter(versions)))
        return

    # Keep the key in the same mutable checkout as the hashes being updated;
    # the executed script may itself live in the Nix store.
    release = signed_release(fetch("dists/stable/InRelease"), key_file, args.gpg, args.gpgv)
    sources = {
        platform: source(platform, architecture, release)
        for platform, architecture in PLATFORMS.items()
    }
    versions = {item["version"] for item in sources.values()}
    if len(versions) != 1:
        raise ValueError(f"OpenAI architecture versions differ: {sorted(versions)}")
    for platform, item in sources.items():
        old = current.get("sources", {}).get(platform, {}).get("version", "")
        if old and item["version"] != old and not should_update(old, item["version"]):
            raise ValueError(f"refusing to downgrade {platform} from {old} to {item['version']}")
    if current.get("sources") == sources:
        print("chatgpt: already up to date")
        return
    save_json(hashes_file, {"sources": sources})
    print(f"chatgpt: updated to {next(iter(versions))}")


if __name__ == "__main__":
    main()
