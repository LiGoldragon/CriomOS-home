{ inputs, pkgs, ... }:
let
  flowId = inputs.harness.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
pkgs.runCommand "flow-id-home-package" { } ''
  test -x ${flowId}/bin/flow-id
  touch "$out"
''
