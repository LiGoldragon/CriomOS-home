#!/usr/bin/env python3
"""Suppress the single Linux Node process-report guard in ChatGPT's ASAR."""

from pathlib import Path
import sys


def main() -> None:
    asar = Path(sys.argv[1])
    source = asar.read_bytes()
    target = b"isLinux() && process.report"
    replacement = b"false /* nix:skip report */"
    if source.count(target) != 1:
        raise SystemExit("vendor ASAR no longer has exactly one process-report guard")
    if len(target) != len(replacement):
        raise SystemExit("process-report replacement must preserve ASAR byte offsets")
    asar.write_bytes(source.replace(target, replacement))


if __name__ == "__main__":
    main()
