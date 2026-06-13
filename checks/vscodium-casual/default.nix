{ pkgs, ... }:

let
  codiumPackage = pkgs.callPackage ../../packages/vscodium-casual { };
in
pkgs.runCommand "vscodium-casual-check" { } ''
  wrapper="${codiumPackage}/bin/codium"

  grep -F -- "--disable-extension rust-lang.rust-analyzer" "$wrapper"
  grep -F -- "--disable-extension vscode.typescript-language-features" "$wrapper"

  touch "$out"
''
