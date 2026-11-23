{ inputs, pkgs, ... }:
let
  owned = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
in
pkgs.runCommand "claude-native-session" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -eu
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  cd "$HOME"
  timeout 50s python3 ${./session.py} ${pkgs.lib.getExe owned.claudeCodePackage}
  touch "$out"
''
