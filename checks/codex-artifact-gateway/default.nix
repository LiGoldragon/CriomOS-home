{ pkgs, ... }:
let
  gateway = pkgs.callPackage ../../packages/codex-artifact-gateway { };
in
pkgs.runCommand "codex-artifact-gateway-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.python3
    ];
  }
  ''
    set -eu
    PYTHONDONTWRITEBYTECODE=1 timeout 30s \
      python3 ${./test_gateway.py} ${gateway}/libexec/codex-artifact-gateway/gateway.py
    touch "$out"
  ''
