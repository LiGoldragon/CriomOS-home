#!/usr/bin/env python3
"""Refresh Claude Code's signed platform manifest pins."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[2] / "scripts"))

from owned_ai_updater import (  # noqa: E402
    fetch_json,
    fetch_text,
    hex_to_sri,
    load_json,
    resolve_checkout_root,
    save_json,
    should_update,
)


RELEASE_BASE = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
PLATFORMS = {
    "x86_64-linux": "linux-x64",
    "aarch64-linux": "linux-arm64",
    "aarch64-darwin": "darwin-arm64",
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
    root = resolve_checkout_root(args.root, "claude-code")
    hashes_file = root / "owned-agents" / "claude-code" / "hashes.json"
    current = load_json(hashes_file)
    if args.show_current:
        print(current["version"])
        return

    version = fetch_text(f"{RELEASE_BASE}/latest").strip()
    if not should_update(current["version"], version):
        print("claude-code: already up to date")
        return

    manifest = fetch_json(f"{RELEASE_BASE}/{version}/manifest.json")
    hashes = {}
    for platform, upstream_platform in PLATFORMS.items():
        checksum = manifest["platforms"][upstream_platform]["checksum"]
        hashes[platform] = hex_to_sri(checksum)
    save_json(hashes_file, {"version": version, "hashes": hashes})
    print(f"claude-code: updated to {version}")


if __name__ == "__main__":
    main()
