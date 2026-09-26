{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        size = "Min"; useColemak = false; hasPublicKey = false; gitSigningKey = "";
        matrixId = ""; isMultimediaDev = false; emailAddress = "herdr-codex-check@example.invalid";
        githubId = "herdr-codex-check"; name = "herdr-codex-check"; publicKeys = [ ];
      };
      horizon.node = { name = "herdr-codex-check"; machine.architecture = "x86_64"; };
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [ ../../modules/home/profiles/min/default.nix {
      home = { username = "herdr-codex-check"; homeDirectory = "/home/herdr-codex-check"; stateVersion = "26.11"; };
    } ];
  };
  hook = homeConfiguration.config.home.file.".codex-next/herdr-agent-state.sh".source;
  # The installed hook is the pinned Herdr's own asset; its integration
  # version is whatever that Herdr release ships, read from the same source.
  upstreamHook = builtins.readFile "${inputs.herdr}/src/integration/assets/codex/herdr-agent-state.sh";
  upstreamVersionLine = pkgs.lib.findFirst (
    line: pkgs.lib.hasPrefix "# HERDR_INTEGRATION_VERSION=" line
  ) (throw "pinned Herdr hook declares no HERDR_INTEGRATION_VERSION") (pkgs.lib.splitString "\n" upstreamHook);
  upstreamVersion = pkgs.lib.removePrefix "# " upstreamVersionLine;
  hookMerge = pkgs.writeText "herdr-codex-next-hook-merge" homeConfiguration.config.home.activation.mergeCodexNextHerdrSessionHook.data;
in
assert pkgs.lib.hasInfix "HERDR_INTEGRATION_ID=codex" (builtins.readFile hook);
assert pkgs.lib.hasInfix upstreamVersion (builtins.readFile hook);
pkgs.runCommand "herdr-codex-integration" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq ]; } ''
  set -eu
  home="$TMPDIR/home"
  mkdir -p "$home/.codex-next"
  cat > "$home/.codex-next/hooks.json" <<'JSON'
  {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash '/tmp/foreign.sh' session","timeout":10},{"type":"command","command":"bash '/home/test/.codex-next/herdr-agent-state.sh' session","timeout":10}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"echo preserve"}]}]}}
  JSON
  HOME="$home" ${pkgs.bash}/bin/bash ${hookMerge}
  test "$( ${pkgs.jq}/bin/jq '[.hooks.SessionStart[].hooks[] | select(.command | contains("/home/test/.codex-next/herdr-agent-state.sh"))] | length' "$home/.codex-next/hooks.json" )" = 0
  test "$( ${pkgs.jq}/bin/jq '[.hooks.SessionStart[].hooks[] | select(.command | contains("/.codex-next/herdr-agent-state.sh"))] | length' "$home/.codex-next/hooks.json" )" = 1
  test "$( ${pkgs.jq}/bin/jq '[.hooks.SessionStart[].hooks[] | select(.command | contains("/tmp/foreign.sh"))] | length' "$home/.codex-next/hooks.json" )" = 1
  test "$( ${pkgs.jq}/bin/jq -r '.hooks.PreToolUse[0].hooks[0].command' "$home/.codex-next/hooks.json" )" = preserve
  touch "$out"
''
