{ pkgs, ... }:

let
  codiumPackage = pkgs.callPackage ../../packages/vscodium-casual { };
  codiumModule = ../../modules/home/vscodium/vscodium/default.nix;
in
pkgs.runCommand "vscodium-casual-check" { } ''
  wrapper="${codiumPackage}/bin/codium"

  grep -F -- "--disable-extension rust-lang.rust-analyzer" "$wrapper"
  grep -F -- "--disable-extension vscode.typescript-language-features" "$wrapper"
  grep -F -- "--disable-extension vscode.css-language-features" "$wrapper"
  grep -F -- "--disable-extension vscode.html-language-features" "$wrapper"
  grep -F -- "--disable-extension vscode.json-language-features" "$wrapper"
  grep -F -- "--disable-extension vscode.php-language-features" "$wrapper"
  grep -F -- '"nix.enableLanguageServer" = false;' "$codiumModule"
  grep -F -- '"nix.serverPath" = null;' "$codiumModule"
  grep -F -- '"rust-analyzer.server.path" = null;' "$codiumModule"
  grep -F -- '"git.autoRepositoryDetection" = false;' "$codiumModule"

  touch "$out"
''
