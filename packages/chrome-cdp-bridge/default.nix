{ pkgs, ... }:
# chrome-cdp-bridge — drive the human's REAL, logged-in Chrome profile with a
# local-LLM browser agent, bypassing the Chrome 136+ block on the external
# --remote-debugging-port for the default profile (Spirit 5g4d).
#
# Two artifacts ship from this package:
#
#   1. The relay (relay.mjs + the `ws` npm dependency) exposed as the
#      `chrome-cdp-bridge-relay` binary. It listens on 127.0.0.1:9333, accepts
#      the outbound WebSocket from the in-browser extension, and re-publishes a
#      BROWSER-LEVEL CDP endpoint (http://127.0.0.1:9333 -> /json/version) that
#      browser-use targets via --cdp-url. The relay synthesises the browser-level
#      Target domain over the single attached tab — the part naive extension
#      relays get wrong (they fail with "Target.attachToBrowserTarget: Not
#      allowed"). See relay.mjs header.
#
#   2. The unpacked Chrome extension directory ($out/share/chrome-cdp-bridge/
#      extension), to be loaded ONCE via chrome://extensions -> Load unpacked.
#      Chrome forbids programmatic load of an arbitrary unpacked extension into
#      the real profile, so this is a deliberate one-time MANUAL step — which is
#      also the right consent boundary: the human installs the capability that
#      grants control of their logged-in browser. The path is printed by the
#      `chrome-cdp-bridge-extension-path` helper.
#
# Packaged like packages/playwright-cli: buildNpmPackage with browser downloads
# off, node from nixpkgs, makeWrapper for the bin. The local-Gemma + gopass-token
# wiring lives in modules/home/profiles/max/browser-use.nix, not here.
let
  bridge = pkgs.buildNpmPackage {
    pname = "chrome-cdp-bridge";
    version = "0.1.0";

    src = ./.;

    npmDepsHash = "sha256-h4J3qVVazU9bLOp+JxFjyQ8gTtPwUh1xy/TyGQnskz4=";

    dontNpmBuild = true;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/chrome-cdp-bridge"
      cp -r node_modules relay.mjs package.json package-lock.json \
        "$out/lib/chrome-cdp-bridge/"

      # The unpacked extension directory, loaded manually once via
      # chrome://extensions -> Load unpacked.
      mkdir -p "$out/share/chrome-cdp-bridge"
      cp -r extension "$out/share/chrome-cdp-bridge/extension"

      mkdir -p "$out/bin"
      makeWrapper "${pkgs.nodejs}/bin/node" "$out/bin/chrome-cdp-bridge-relay" \
        --add-flags "$out/lib/chrome-cdp-bridge/relay.mjs" \
        --set NODE_PATH "$out/lib/chrome-cdp-bridge/node_modules"

      # Print the unpacked-extension path for the one-time Load unpacked step.
      makeWrapper "${pkgs.coreutils}/bin/echo" \
        "$out/bin/chrome-cdp-bridge-extension-path" \
        --add-flags "$out/share/chrome-cdp-bridge/extension"

      runHook postInstall
    '';

    meta = {
      description = "chrome.debugger extension + CDP relay to drive the real Chrome profile";
      mainProgram = "chrome-cdp-bridge-relay";
    };
  };
in
bridge
