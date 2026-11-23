{ inputs, pkgs, ... }:
let
  codex = pkgs.callPackage ../../owned-agents/codex { };
  herdr = pkgs.callPackage ../../packages/herdr { inherit inputs; };
in
pkgs.runCommand "herdr-codex-tui" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -eu
  export HOME="$TMPDIR/home"
  export PATH="${pkgs.lib.makeBinPath [ pkgs.bubblewrap ]}:$PATH"
  mkdir -p "$HOME"
  cd "$HOME"
  timeout 60s python3 ${./launch.py}     ${pkgs.lib.getExe herdr} ${pkgs.lib.getExe codex} '${codex.version}'     "${pkgs.bashInteractive}/bin/bash"
  touch "$out"
''
