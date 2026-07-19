{ pkgs, ... }:

let
  orchestrateModule = ../../modules/home/profiles/min/orchestrate.nix;
in
pkgs.runCommand "orchestrate-service-path" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  set -eu

  grep -F 'Environment = "PATH=''${lib.makeBinPath [ pkgs.gnupg pkgs.jujutsu ]}";' ${orchestrateModule}

  touch "$out"
''
