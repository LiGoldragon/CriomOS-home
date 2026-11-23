{ inputs, pkgs, ... }:
let
  owned = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
in
pkgs.runCommand "codex-native-thread" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -eu
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CODEX_HOME="$HOME/.codex"
  mkdir -p "$CODEX_HOME"
  cd "$HOME"
  timeout 30s python3 ${./thread.py} ${pkgs.lib.getExe owned.codexPackage} '${owned.codexPackage.version}'
  touch "$out"
''
