{
  pkgs,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  leta = pkgs.callPackage ../../packages/leta { };
  rustToolchain = inputs.self.packages.${system}.rust-toolchain;
in
pkgs.runCommand "leta-profile-tools-check"
  {
    nativeBuildInputs = [
      leta
      rustToolchain
      pkgs.typescript-language-server
      pkgs.typescript
      pkgs.gopls
      pkgs.clang-tools
      pkgs.nil
    ];
  }
  ''
    command -v leta
    command -v leta-daemon
    command -v typescript-language-server
    command -v gopls
    command -v rust-analyzer
    command -v clangd
    command -v nil

    leta --help >/dev/null
    leta daemon --help >/dev/null

    touch "$out"
  ''
