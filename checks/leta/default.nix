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
      pkgs.ast-grep
      pkgs.tree-sitter
      pkgs.nil
      pkgs.tokei
      pkgs.scc
    ];
  }
  ''
    command -v leta
    command -v leta-daemon
    command -v typescript-language-server
    command -v gopls
    command -v rust-analyzer
    command -v clangd
    command -v ast-grep
    command -v tree-sitter
    command -v nil
    command -v tokei
    command -v scc

    leta --help >/dev/null
    leta daemon --help >/dev/null
    ast-grep --help >/dev/null
    tree-sitter --version >/dev/null
    tokei --version >/dev/null
    scc --version >/dev/null

    touch "$out"
  ''
