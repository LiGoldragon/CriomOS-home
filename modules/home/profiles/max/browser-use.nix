{
  lib,
  pkgs,
  inputs,
  horizon,
  user,
  ...
}:
# browser-use, wired to the workspace-local Gemma 4 vision model.
#
# browser-use is the popular LLM-driven browser agent. It drives a real
# Chrome over the Chrome DevTools Protocol and reads each page visually
# with a vision LLM, then decides the next action. On CriomOS that vision
# LLM is the local Gemma 4 multimodal model served on the cluster's
# large-AI node (prometheus), NOT a cloud API — so the account/billing
# screenshots browser-use feeds its model stay on-prem (Spirit u275,
# wvgh, 8pgh; privacy WHY in report 62).
#
# Endpoint + token resolution mirrors pi-models.nix exactly:
#   - baseUrl from the projected Horizon large-AI(-router) node, port 11434, /v1
#   - the OpenAI-compatible token is read at RUNTIME from gopass
#     (goldragon.criome/local-llm-api-token); the bytes never enter Nix.
#
# Gating: the same Large tier as Chrome (max/default.nix `size.large`
# block) — browser-use without Chrome is useless and its closure is large
# (264-package Python env). Spirit bxe9: just packaged + on PATH; any
# harness/agent calls `browser-use` like a shell command. The library
# (`browser-use-python`) and a ready-made local-Gemma+CDP driver
# (`browser-use-local`) are also exposed for scripted scout flows
# (report 61's DigitalOcean token workflow, Spirit 7hmc/5g4d/7o4q).
let
  inherit (user) size;

  browserUse = pkgs.callPackage ../../../../packages/browser-use { inherit inputs; };

  # chrome-cdp-bridge — the in-browser chrome.debugger extension + CDP relay
  # that lets browser-use drive the human's REAL, logged-in Chrome profile
  # (Spirit 5g4d), bypassing the Chrome 136+ block on the external
  # --remote-debugging-port for the default profile. The relay re-publishes a
  # browser-level CDP endpoint (http://127.0.0.1:9333) that browser-use targets
  # via --cdp-url; the unpacked extension is loaded ONCE via
  # chrome://extensions -> Load unpacked (Chrome forbids programmatic load of an
  # arbitrary extension — that one-time manual step is also the consent gate).
  chromeCdpBridge = pkgs.callPackage ../../../../packages/chrome-cdp-bridge { };

  # The relay (and the extension) share a token with the in-browser extension so
  # only the consented extension can dial the loopback relay. Read from gopass at
  # exec time, never in Nix/logs. Reuses the same path the playwright-cli
  # extension wrapper already seeds.
  bridgeTokenGopassPath = "chrome-browser/playwright-mcp-extension-token";

  # Same endpoint projection as pi-models.nix: prefer the large-AI router,
  # fall back to a plain large-AI node. Port + /v1 from the model catalog.
  inventory = builtins.fromJSON (builtins.readFile (inputs.criomos-lib + "/data/largeAI/llm.json"));
  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  localBaseUrl =
    if endpointNode != null then
      "http://${endpointNode.criomeDomainName}:${toString (inventory.serverPort or 11434)}/v1"
    else
      null;

  # gemma-4-26b-a4b is the multimodal (mmproj-F16) variant verified for
  # image requests in system-operator report 173 — the right default for a
  # vision-driven browser agent. Pinned by name so the agent always reads
  # the page with the on-prem vision model.
  localVisionModel = "gemma-4-26b-a4b";
  localLlmGopassPath = "goldragon.criome/local-llm-api-token";

  gopass = "${pkgs.gopass}/bin/gopass";

  # Shared preamble: export OPENAI_BASE_URL/OPENAI_API_KEY/model so that
  # any browser-use code path using ChatOpenAI defaults to the local Gemma
  # endpoint. The token is sourced from gopass at exec time and never
  # printed. Honour pre-set values so an explicit override still works.
  gemmaEnvPreamble = ''
    set -eu
    : "''${OPENAI_BASE_URL:=${localBaseUrl}}"
    : "''${BROWSER_USE_VISION_MODEL:=${localVisionModel}}"
    if [ -z "''${OPENAI_API_KEY:-}" ]; then
      OPENAI_API_KEY="$(${gopass} show -o ${localLlmGopassPath} 2>/dev/null || true)"
      if [ -z "$OPENAI_API_KEY" ]; then
        echo "browser-use: gopass ${localLlmGopassPath} returned an empty local-LLM token" >&2
        exit 1
      fi
    fi
    export OPENAI_BASE_URL OPENAI_API_KEY BROWSER_USE_VISION_MODEL
  '';

  # `browser-use-gemma` — the browser-use CLI with the local-Gemma env
  # pre-loaded. Wraps every console-script arg through to the packaged CLI.
  browserUseGemma = pkgs.writeShellApplication {
    name = "browser-use-gemma";
    runtimeInputs = [
      pkgs.gopass
      browserUse
    ];
    text = ''
      ${gemmaEnvPreamble}
      exec browser-use "$@"
    '';
  };

  # `browser-use-local` — a library-mode driver: run ONE task against a
  # Chrome already listening on a CDP url, with Gemma 4 as the vision LLM.
  # This is the report-61 scout shape — connect over CDP to a supervised,
  # human-visible Chrome (non-default --user-data-dir per the Chrome-136+
  # rule), scan + act with the on-prem model. Usage:
  #   browser-use-local <cdp-url> <task...>
  # e.g. browser-use-local http://127.0.0.1:9222 "report the page title"
  localDriver = pkgs.writeShellApplication {
    name = "browser-use-local";
    runtimeInputs = [
      pkgs.gopass
      browserUse
    ];
    text = ''
      ${gemmaEnvPreamble}
      if [ "$#" -lt 2 ]; then
        echo "usage: browser-use-local <cdp-url> <task...>" >&2
        echo "  drives the Chrome at <cdp-url> with the local Gemma 4 vision model" >&2
        exit 2
      fi
      CDP_URL="$1"; shift
      TASK="$*"
      export BROWSER_USE_CDP_URL="$CDP_URL" BROWSER_USE_TASK="$TASK"
      exec browser-use-python ${../../../../packages/browser-use/browser-use-local-driver.py}
    '';
  };

  # `browser-use-attach` — drive the human's REAL Chrome profile end to end.
  #
  # Flow (the supervised-scout discipline, Spirit 7hmc/5g4d):
  #   1. The human has loaded the chrome-cdp-bridge extension ONCE (Load
  #      unpacked; `browser-use-attach --extension-path` prints the dir) and
  #      clicked its toolbar icon on the ONE tab they consent to expose.
  #   2. This wrapper sources the bridge token from gopass, starts the loopback
  #      relay (127.0.0.1:9333), waits for the extension to attach that tab,
  #      then runs ONE browser-use task with the local Gemma 4 against the
  #      relay's browser-level CDP url. The relay stops when the task ends.
  #
  # The agent never opens new tabs or touches other tabs; it drives only the
  # consented tab. Usage:
  #   browser-use-attach <task...>
  #   browser-use-attach --extension-path     # print the unpacked-extension dir
  attachDriver = pkgs.writeShellApplication {
    name = "browser-use-attach";
    runtimeInputs = [
      pkgs.gopass
      pkgs.curl
      pkgs.coreutils
      browserUse
      chromeCdpBridge
    ];
    text = ''
      if [ "''${1:-}" = "--extension-path" ]; then
        chrome-cdp-bridge-extension-path
        exit 0
      fi
      ${gemmaEnvPreamble}
      if [ "$#" -lt 1 ]; then
        echo "usage: browser-use-attach <task...>" >&2
        echo "       browser-use-attach --extension-path   # print extension dir to Load unpacked" >&2
        echo "" >&2
        echo "Drives the tab you clicked the CriomOS CDP Bridge extension on," >&2
        echo "in your REAL Chrome profile, with the local Gemma 4 vision model." >&2
        exit 2
      fi
      TASK="$*"

      # Bridge token (shared with the extension). Empty is allowed (loopback
      # only), but seeding it in gopass + chrome.storage is recommended.
      CHROME_CDP_BRIDGE_TOKEN="$(${pkgs.gopass}/bin/gopass show -o ${bridgeTokenGopassPath} 2>/dev/null || true)"
      export CHROME_CDP_BRIDGE_TOKEN
      PORT="''${CHROME_CDP_BRIDGE_PORT:-9333}"
      export CHROME_CDP_BRIDGE_PORT="$PORT"

      # Start the relay in the background; always stop it on exit.
      chrome-cdp-bridge-relay &
      RELAY_PID=$!
      # shellcheck disable=SC2064
      trap "kill $RELAY_PID 2>/dev/null || true" EXIT INT TERM

      # Wait for the relay's CDP discovery endpoint.
      for _ in $(seq 1 30); do
        if curl -fsS "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
          break
        fi
        sleep 0.5
      done

      echo "browser-use-attach: relay is up on http://127.0.0.1:$PORT" >&2
      echo "browser-use-attach: click the CriomOS CDP Bridge toolbar icon on the" >&2
      echo "  tab you want to expose (badge shows ON), then this drives it." >&2

      export BROWSER_USE_CDP_URL="http://127.0.0.1:$PORT" BROWSER_USE_TASK="$TASK"
      exec browser-use-python ${../../../../packages/browser-use/browser-use-local-driver.py}
    '';
  };
in
lib.mkIf (size.large && endpointNode != null) {
  home.packages = [
    # The packaged browser-use CLI on PATH (Spirit bxe9). Exposes
    # `browser-use`, `bu`, `browseruse`, `browser-use-tui`, and the
    # collision-free library interpreter `browser-use-python`.
    browserUse
    # Local-Gemma-vision wrappers.
    browserUseGemma
    localDriver
    # Real-profile attach: the chrome.debugger bridge relay/extension + the
    # `browser-use-attach` driver. Exposes `chrome-cdp-bridge-relay`,
    # `chrome-cdp-bridge-extension-path`, and `browser-use-attach` on PATH.
    chromeCdpBridge
    attachDriver
  ];
}
