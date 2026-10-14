"""Merge immutable share trees, replacing only witnessed package-owned leaves."""
import json
import os
import sys
from pathlib import Path


def leaves(root):
    result = {}

    def visit(directory, relative, ancestors):
        real = directory.resolve(strict=True)
        if real in ancestors:
            raise ValueError("share directory cycle")
        for entry in sorted(directory.iterdir()):
            name = relative / entry.name
            if entry.is_dir():
                visit(entry, name, ancestors | {real})
            else:
                entry.resolve(strict=True)
                result[str(name)] = entry

    visit(root, Path(), set())
    return result


def merge(baseline, old, new, output, manifest):
    base, previous, selected = map(leaves, (baseline, old, new))
    if set(previous) != set(manifest["old"]) or set(selected) != set(manifest["new"]):
        raise ValueError("package share manifest changed")
    for name in set(previous) | set(selected):
        if name in base and (
            name not in previous or base[name].resolve() != previous[name].resolve()
        ):
            raise ValueError("foreign share collision: " + name)
    retained = {name: path for name, path in base.items() if name not in previous}
    for name, path in sorted((retained | selected).items()):
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(path)


if __name__ == "__main__":
    baseline, old, new, output = map(Path, sys.argv[1:5])
    merge(baseline, old, new, output, json.loads(sys.argv[5]))
