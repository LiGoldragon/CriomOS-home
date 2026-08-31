#!/usr/bin/env python3
"""Refresh the pinned Codex source and rusty-v8 artifacts.

The release/tag and Cargo.lock discovery follows the pinned upstream Codex
updater flow.  Only this package's hashes file is changed; Cargo dependency
hash discovery is delegated to the package's own Nix build.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

from owned_ai_updater import (  # noqa: E402
    DUMMY_SHA256_HASH,
    fetch_bytes,
    fetch_json,
    save_json,
    load_json,
    resolve_checkout_root,
    should_update,
    update_dependency_hash,
    url_hash,
)


RUSTY_V8_PLATFORMS = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "aarch64-linux": "aarch64-unknown-linux-gnu",
    "aarch64-darwin": "aarch64-apple-darwin",
}


def latest_version() -> str:
    releases = fetch_json("https://api.github.com/repos/openai/codex/releases?per_page=30")
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        tag = release.get("tag_name", "")
        match = re.fullmatch(r"rust-v(.+)", tag)
        if match:
            return match.group(1)
    raise RuntimeError("OpenAI Codex releases did not contain a rust-v<version> tag")


def rusty_v8(version: str, previous: dict | None) -> dict:
    cargo_lock = fetch_bytes(
        f"https://raw.githubusercontent.com/openai/codex/rust-v{version}/codex-rs/Cargo.lock"
    ).decode()
    match = re.search(r'name = "v8"\nversion = "([^"]+)"', cargo_lock)
    if not match:
        raise RuntimeError("Codex Cargo.lock did not contain the v8 package version")
    v8_version = match.group(1)
    if previous and previous.get("version") == v8_version:
        return previous

    profile = "ptrcomp_sandbox_release"
    base_url = f"https://github.com/openai/codex/releases/download/rusty-v8-v{v8_version}"
    return {
        "version": v8_version,
        "profile": profile,
        "baseUrl": base_url,
        "hashes": {
            platform: url_hash(
                f"{base_url}/librusty_v8_{profile}_{target}.a.gz"
            )
            for platform, target in RUSTY_V8_PLATFORMS.items()
        },
        "srcBindingHashes": {
            platform: url_hash(f"{base_url}/src_binding_{profile}_{target}.rs")
            for platform, target in RUSTY_V8_PLATFORMS.items()
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--show-current", action="store_true", help="print the pinned version without network access"
    )
    parser.add_argument(
        "--root", type=Path, help="CriomOS-home checkout to update (default: current directory)"
    )
    args = parser.parse_args()
    root = resolve_checkout_root(args.root, "codex")
    hashes_file = root / "owned-agents" / "codex" / "hashes.json"
    data = load_json(hashes_file)
    if args.show_current:
        print(data["version"])
        return

    version = latest_version()
    current = data["version"]
    print(f"Current: {current}, latest: {version}")
    if not should_update(current, version):
        print("codex: already up to date")
        return

    tag = f"rust-v{version}"
    source_url = f"https://github.com/openai/codex/archive/refs/tags/{tag}.tar.gz"
    updated = {
        "version": version,
        "hash": url_hash(source_url, unpack=True),
        "cargoHash": DUMMY_SHA256_HASH,
        "librusty_v8": rusty_v8(version, data.get("librusty_v8")),
    }
    update_dependency_hash(".#codex", "cargoHash", hashes_file, updated)
    save_json(hashes_file, updated)
    print(f"codex: updated to {version}")


if __name__ == "__main__":
    main()
