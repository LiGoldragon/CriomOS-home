{ pkgs, ... }:

pkgs.runCommand "emacs-rust-analyzer-autostart-check" { } ''
  set -eu

  emacsModule=${../../modules/home/profiles/med/emacs.nix}

  grep -F -- '((rust-mode rust-ts-mode) . ("rust-analyzer"))' "$emacsModule"
  ! grep -F -- ':hook (rust-mode . eglot-ensure)' "$emacsModule"

  touch "$out"
''
