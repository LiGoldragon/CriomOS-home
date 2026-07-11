{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  spiritJudge = inputs.spirit-judge.packages.${system}.default;
in
pkgs.runCommand "spirit-judge-cli-contract" { } ''
  set -eu

  # This calls the real package locked by this flake. It proves only the
  # unauthenticated CLI boundary: no socket is opened and no provider is called.
  if "${spiritJudge}/bin/spirit-judge" > output 2>&1; then
    exit 1
  fi
  grep -q 'serve --socket <path>' output
  touch "$out"
''
