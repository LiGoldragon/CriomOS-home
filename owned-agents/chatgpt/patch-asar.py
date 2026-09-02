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

# Desktop separately synchronizes its bundled App Tools MCP server through
# config/batchWrite for every local app-server connection.  That path survives
# the resolver override above and produces a `codex_app` entry which Codex
# 0.152.1 rejects before either a fresh thread or a resumed thread can run.
# Desktop is an ordinary WebSocket client of the shared daemon, so it must not
# create a private App Tools configuration at all.
NO_APP_TOOLS_CONFIG_OVERRIDE = (
    re.compile(
        rb"async function (?P<name>[\w$]+)\(\{hostConfig:[\w$]+,resourcesPath:[\w$]+=process\.resourcesPath\}\)"
        rb"\{[\s\S]*?\}(?=function [\w$]+\(e\)\{return [\w$]+\.warning\(`Codex app tools unavailable)"
    ),
    # The resolver is one producer, but request construction is a separate
    # boundary.  Keep the resolver empty and install the sanitizer alongside
    # it, where the available padding makes a byte-length-preserving patch
    # possible.  The helpers below use the bundle's existing li/ui/gte
    # predicates, which are function declarations and therefore hoisted.
    lambda m: (
        b"async function "
        + m["name"]
        + b"(){return[]}"
        + b"function Tge(e){if(!e||!e.params||!ui(e.params.config)||![`thread/start`,`thread/resume`,`thread/fork`].includes(e.method))return e;"
        + b"return{...e,params:{...e.params,config:CriomWithoutCodexApp(e.params.config)}}}"
        + b"function CriomWithoutCodexApp(e,t=``){return Object.fromEntries(Object.entries(e).flatMap(([e,n])=>{"
        + b"let r=gte(t,e);if(r===`mcp_servers.codex_app`||r.startsWith(`mcp_servers.codex_app.`))return[];"
        + b"if(ui(n)&&`mcp_servers.codex_app`.startsWith(`${r}.`)){let t=CriomWithoutCodexApp(n,r);"
        + b"return Object.keys(t).length===0?[]:[[e,t]]}return[[e,n]]}))}"
    ),
)

# These two helpers bypass the resolver and synthesize the invalid private
# stdio object directly for background threads.  Preserve caller config and
# reasoning effort, but remove the retired App Tools server itself.
REMOVE_CJ_CODEX_APP = (
    re.compile(
        rb"config:\{\.\.\.(?P<config>[\w$]+),\"mcp_servers\.codex_app\":"
        rb"\{enabled:!1,command:``\},model_reasoning_effort:(?P<effort>[\w$]+)\}"
    ),
    lambda m: b"config:{..." + m["config"] + b",model_reasoning_effort:" + m["effort"] + b"}",
)

REMOVE_H0_CODEX_APP = (
    re.compile(
        rb"v=\{\.\.\.(?P<config>s),\"mcp_servers\.codex_app\":"
        rb"\{enabled:!1,command:``\},model_reasoning_effort:(?P<effort>[\w$]+)\}"
    ),
    lambda m: b"v={..." + m["config"] + b",model_reasoning_effort:" + m["effort"] + b"}",
)

# _T is the legacy serialized fallback.  It is not currently a proven caller,
# but leaving it executable would retain a third invalid producer.
REMOVE_APP_TOOLS_SERIALIZED_FALLBACK = (
    re.compile(
        rb"function (?P<name>[\w$]+)\(e\)\{return (?P<logger>[\w$]+)\.warning\("
        rb"`Codex app tools unavailable for this Core launch`,"
        rb"\{safe:\{reason:e\},sensitive:\{\}\}\),"
        rb"\[`mcp_servers\.codex_app=\{command=\"\",enabled=false\}`\]\}"
    ),
    lambda m: b"function " + m["name"] + b"(e){return[]}",
)

# Artifact-session interception is intentionally stdio-only.  This common
# thread-request wrapper must nevertheless sanitize the retired private App
# Tools capability on every outgoing transport, including WebSocket.
SANITIZE_THREAD_REQUEST_CONFIG = (
    re.compile(
        rb"function (?P<name>[\w$]+)\(\{getHostLifecycle:(?P<host>[\w$]+),"
        rb"getExpectedThreadConfig:(?P<config>[\w$]+),isLocalStdio:(?P<stdio>[\w$]+)\}\)"
        rb"\{if\((?P=stdio)\(\)\)return (?P<request>[\w$]+)=>"
        rb"(?P=stdio)\(\)\?(?P<intercept>[\w$]+)\((?P=request),"
        rb"(?P<is_thread>[\w$]+)\((?P=request)\)&&(?P<available>[\w$]+)\((?P=request)\)"
        rb"\?(?P=host)\(\):null,(?P=config)\):(?P=request)\}"
    ),
    lambda m: (
        b"function "
        + m["name"]
        + b"({getHostLifecycle:"
        + m["host"]
        + b",getExpectedThreadConfig:"
        + m["config"]
        + b",isLocalStdio:"
        + m["stdio"]
        + b"}){return "
        + m["request"]
        + b"=>Tge("
        + m["stdio"]
        + b"()?"
        + m["intercept"]
        + b"("
        + m["request"]
        + b","
        + m["is_thread"]
        + b"("
        + m["request"]
        + b")&&"
        + m["available"]
        + b"("
        + m["request"]
        + b")?"
        + m["host"]
        + b"():null,"
        + m["config"]
        + b"):"
        + m["request"]
        + b")}"
    ),
)

PATCHES: list[tuple[re.Pattern[bytes], Callable[[re.Match[bytes]], bytes]]] = [
    SKIP_PROCESS_REPORT,
    COPY_PLUGINS_WRITABLE,
    SHARED_APP_SERVER,
    NO_APP_TOOLS_CONFIG_OVERRIDE,
    REMOVE_CJ_CODEX_APP,
    REMOVE_H0_CODEX_APP,
    REMOVE_APP_TOOLS_SERIALIZED_FALLBACK,
    SANITIZE_THREAD_REQUEST_CONFIG,
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
