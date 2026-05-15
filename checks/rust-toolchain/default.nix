{ inputs, pkgs, ... }:

let
  rustToolchain = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
in
pkgs.runCommand "rust-toolchain-check" { nativeBuildInputs = [ rustToolchain ]; } ''
  set -eu

  cargo --version
  rustc --version
  rustfmt --version
  cargo fmt --version
  cargo clippy --version
  rust-analyzer --version

  touch "$out"
''
