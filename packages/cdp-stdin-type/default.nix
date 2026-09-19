{ pkgs, ... }:
# cdp-stdin-type — the stdin interface a browser does not have.
#
# The living signs in to their OWN accounts (Claude, ChatGPT) in a browser that
# runs on a rented server. The password lives in gopass on their own laptop; it
# must never be written to that server's disk, never appear in argv or the
# environment, never be seen by an agent. The workspace secrets discipline
# answers that shape with one rule: pipe the producer straight into the
# consumer's official stdin. Browsers have no such interface — so this package
# is it. `cdp-stdin-type` is the consumer at the end of the pipe:
#
#   gopass show -o accounts/anthropic \
#     | ssh -p <port> server cdp-stdin-type --endpoint http://127.0.0.1:9223 \
#         --url-contains claude.ai --submit
#
# It reads the text from stdin (refusing outright to run on a TTY, so it can
# never prompt into an echoing terminal), attaches to one page target's
# webSocketDebuggerUrl, and hands the bytes to Chrome as a single CDP
# `Input.insertText` — an IME-style commit into whatever element the page has
# focused. Its own output is structural: the target id, the url, a success line.
# Never the text, and never its length.
#
# What this genuinely removes: the password on the server's disk, in a process
# argument list, in an environment block, in a shell history, in this tool's
# logs, and in any agent's context. What it does NOT remove, named plainly
# rather than papered over: the kernel pipe carrying the bytes, the SSH
# transport, gopass's own crypto backend on the laptop, and Chrome's process
# memory and network stack — the browser must hold the plaintext to sign in at
# all. That last boundary is the consumer boundary, and it is the point past
# which no tooling can help.
#
# Focus is the caller's business, deliberately: `Input.insertText` types into
# whatever is focused, so the flow that drives the sign-in page (or the human,
# watching the tab through chrome://inspect over an SSH tunnel) clicks the field
# first. This tool does not select, search for, or reason about form fields — a
# smaller surface that cannot be talked into typing a password somewhere else.
#
# Dependency-free by design: node 22 ships a global WebSocket, so unlike
# packages/chrome-cdp-bridge (which needs `ws` and therefore buildNpmPackage)
# this is one script plus a makeWrapper shim, and its closure is just nodejs.
pkgs.stdenvNoCC.mkDerivation {
  pname = "cdp-stdin-type";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/cdp-stdin-type"
    cp cdp-stdin-type.mjs "$out/lib/cdp-stdin-type/"

    mkdir -p "$out/bin"
    makeWrapper "${pkgs.nodejs}/bin/node" "$out/bin/cdp-stdin-type" \
      --add-flags "$out/lib/cdp-stdin-type/cdp-stdin-type.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Pipe stdin into a remote Chrome tab's focused element over CDP, never through argv or a file";
    mainProgram = "cdp-stdin-type";
  };
}
