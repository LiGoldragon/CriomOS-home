{ inputs, pkgs, ... }:
let
  rustToolchain = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
in
pkgs.mkShell {
  packages = [
    pkgs.nixfmt-rfc-style
    pkgs.jq
    rustToolchain
  ];
}
