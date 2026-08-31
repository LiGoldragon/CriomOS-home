#!/usr/bin/env python3
"""Apply byte-length-preserving NixOS patches inside ChatGPT's app.asar."""

import re
import sys
from collections.abc import Callable
from pathlib import Path

SKIP_PROCESS_REPORT = (
    re.compile(rb"isLinux\(\) && process\.report"),
    lambda _m: b"false /* nix:skip report */",
)

COPY_PLUGINS_WRITABLE = (
    re.compile(
        rb"(?P<fn>async function [\w$]+\(e,t\)\{)"
        rb"if\((?P<plat>[\w$]+\.default\.platform)===`darwin`\)"
        rb"(?P<ditto>\{await (?P<exec>[\w$]+)\(`/usr/bin/ditto`,\[`--noqtn`,e,t\]\);return\})"
        rb"if\((?P=plat)!==`win32`\)\{"
        rb"await [\w$]+\.default\.cp\(e,t,\{recursive:!0,verbatimSymlinks:!0\}\);return\}"
    ),
    lambda m: (
        m["fn"]
        + b"let r="
        + m["plat"]
        + b";if(r===`darwin`)"
        + m["ditto"]
        + b"if(r!==`win32`){await "
        + m["exec"]
        + b"(`cp`,[`-r`,e+`/.`,t]);await "
        + m["exec"]
        + b"(`chmod`,[`-R`,`u+w`,t]);return}"
    ),
)

# The native local-daemon branch is used only when no startup configuration
# overrides are supplied.  Desktop's codex_app override creates its private
# Electron App Tools pipe and forces an embedded stdio server, so the shared
# owner is never reached.  Keep the call site but make its override list empty.
SHARED_APP_SERVER = (
    re.compile(rb"getConfigOverrides:\(\)=>[\w$]+\([\w$]+\)"),
    lambda _m: b"getConfigOverrides:()=>[]",
)

PATCHES: list[tuple[re.Pattern[bytes], Callable[[re.Match[bytes]], bytes]]] = [
    SKIP_PROCESS_REPORT,
    COPY_PLUGINS_WRITABLE,
    SHARED_APP_SERVER,
]


def main() -> None:
    asar = Path(sys.argv[1])
    data = asar.read_bytes()
    for pattern, build in PATCHES:
        matches = list(pattern.finditer(data))
        if len(matches) != 1:
            sys.exit(f"expected 1 match for {pattern.pattern[:60]!r}, got {len(matches)}")
        match = matches[0]
        replacement = build(match)
        if len(replacement) > len(match.group(0)):
            sys.exit("replacement is longer than the original asar source")
        data = data[: match.start()] + replacement.ljust(len(match.group(0)), b" ") + data[match.end() :]
    asar.write_bytes(data)


if __name__ == "__main__":
    main()
