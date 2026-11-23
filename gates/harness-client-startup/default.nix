{ inputs, pkgs, ... }:
let
  owned = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  pi = pkgs.callPackage ../../packages/pi { };
in
pkgs.runCommand "harness-client-startup" { } ''
  set -euo pipefail
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  export LINKUP_API_KEY=fixture
  mkdir -p "$HOME"
  {
    ${pkgs.lib.getExe owned.codexPackage} --version
    ${pkgs.lib.getExe owned.claudeCodePackage} --version
    ${pkgs.lib.getExe pkgs.gemini-cli} --version
    ${pkgs.lib.getExe pkgs.opencode} --version
    ${pkgs.lib.getExe pkgs.orca-ide} --version
    ${pkgs.lib.getExe pi} --version
  } | tee "$TMPDIR/versions"
  for v in '${owned.codexPackage.version}' '${owned.claudeCodePackage.version}' \
           '${pkgs.gemini-cli.version}' '${pkgs.opencode.version}' \
           '${pkgs.orca-ide.version}' '${pi.version}'; do
    grep -F "$v" "$TMPDIR/versions"
  done
  touch "$out"
''
