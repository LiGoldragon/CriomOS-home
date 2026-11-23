#!/usr/bin/env python3
"""Update the prebuilt stable release manifest consumed by default.nix."""
from __future__ import annotations

import argparse
import base64
import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))
from owned_ai_updater import fetch_bytes, fetch_json, load_json, resolve_checkout_root, save_json

TARGETS = {"x86_64-linux": "x86_64-unknown-linux-musl", "aarch64-linux": "aarch64-unknown-linux-musl"}
RELEASES = "https://api.github.com/repos/openai/codex/releases"


def artifact_url(version: str, target: str) -> str:
    return f"https://github.com/openai/codex/releases/download/rust-v{version}/codex-package-{target}.tar.gz"


def validate_manifest(data: dict) -> None:
    if set(data) != {"version", "targets"}:
        raise ValueError("Codex manifest holds a version and complete package targets")
    version = data.get("version", "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Stable Codex requires an exact stable version")
    if set(data.get("targets", {})) != set(TARGETS):
        raise ValueError("Release must cover every supported target, and no others")
    for system, target in TARGETS.items():
        row = data["targets"][system]
        if set(row) != {"target", "hash"} or row.get("target") != target:
            raise ValueError("Unsupported target triple")
        value = row.get("hash", "")
        if not value.startswith("sha256-"):
            raise ValueError("Artifact requires a SHA256 SRI hash")
        try:
            digest = base64.b64decode(value[7:], validate=True)
        except ValueError as error:
            raise ValueError("Invalid SHA256 SRI hash") from error
        if len(digest) != 32:
            raise ValueError("Invalid SHA256 digest length")


def release_manifest(release: dict) -> dict:
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"rust-v\d+\.\d+\.\d+", tag):
        raise ValueError("Requested release is not a published stable Codex release")
    version = tag.removeprefix("rust-v")
    assets = {}
    for asset in release.get("assets", []):
        name = asset.get("name")
        if name in assets:
            raise ValueError("Duplicate release artifact")
        assets[name] = asset
    result = {"version": version, "targets": {}}
    for system, target in TARGETS.items():
        name = f"codex-package-{target}.tar.gz"
        asset = assets.get(name)
        if asset is None:
            raise ValueError(f"Missing required release artifact: {name}")
        if asset.get("browser_download_url") != artifact_url(version, target):
            raise ValueError("Artifact URL does not match the exact release and target")
        digest = asset.get("digest", "")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError(f"Missing SHA256 release digest: {name}")
        result["targets"][system] = {
            "target": target,
            "hash": "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode(),
        }
    validate_manifest(result)
    for row in result["targets"].values():
        url = artifact_url(version, row["target"])
        actual = "sha256-" + base64.b64encode(hashlib.sha256(fetch_bytes(url)).digest()).decode()
        if actual != row["hash"]:
            raise ValueError(f"Release artifact digest mismatch: {url}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--show-current", action="store_true", help="read the consumed version offline")
    parser.add_argument("--version", help="select an exact stable release instead of latest")
    parser.add_argument("--root", type=Path, help="exact CriomOS-home source checkout")
    args = parser.parse_args()
    root = resolve_checkout_root(args.root, "codex")
    path = root / "owned-agents/codex/hashes.json"
    current = load_json(path)
    validate_manifest(current)
    if args.show_current:
        print(current["version"])
        return
    if args.version and not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("--version must name an exact stable release")
    suffix = f"tags/rust-v{args.version}" if args.version else "latest"
    release = fetch_json(f"{RELEASES}/{suffix}")
    if args.version and release.get("tag_name") != f"rust-v{args.version}":
        raise ValueError("Release metadata does not match the requested version")
    updated = release_manifest(release)
    if updated["version"] == current["version"]:
        if updated != current:
            raise ValueError("Immutable release identity changed; manifest left untouched")
        print(f"codex: already at {current['version']}")
        return
    save_json(path, updated)
    print(f"codex: updated to {updated['version']}")


if __name__ == "__main__":
    main()
