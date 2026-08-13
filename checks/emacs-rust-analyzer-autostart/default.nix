{ pkgs, ... }:

pkgs.runCommand "emacs-rust-analyzer-autostart-check" { } ''
  set -eu

  emacsModule=${../../modules/home/profiles/med/emacs.nix}

  grep -F -- '((rust-mode rust-ts-mode) . ("rust-analyzer"))' "$emacsModule"
  ! grep -F -- ':hook (rust-mode . eglot-ensure)' "$emacsModule"
  ! grep -F -- 'projectile-mode +1' "$emacsModule"
  ! grep -F -- 'org-roam-db-autosync-mode 1' "$emacsModule"
  ! grep -F -- 'global-flycheck-eglot-mode 1' "$emacsModule"
  ! grep -F -- 'flycheck-mode)' "$emacsModule"
  ! grep -F -- 'nixfmt-on-save-mode' "$emacsModule"
  ! grep -F -- 'shfmt-on-save-mode' "$emacsModule"
  ! grep -F -- 'rust-format-on-save t' "$emacsModule"
  ! grep -F -- 'format-all-mode)' "$emacsModule"

  touch "$out"
''
