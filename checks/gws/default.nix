{ pkgs, inputs, ... }:
let
  gws = pkgs.callPackage ../../packages/gws { inherit inputs; };
in
pkgs.runCommand "gws-check" { nativeBuildInputs = [ gws ]; } ''
  gws --help >/dev/null
  gws auth --help >/dev/null
  gws auth login --help >/dev/null
  gws auth status >/dev/null
  touch $out
''
