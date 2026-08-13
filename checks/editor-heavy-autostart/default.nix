{ pkgs, ... }:

pkgs.runCommand "editor-heavy-autostart-check" { } ''
  set -eu

  neovimModule=${../../modules/home/neovim/neovim/default.nix}

  grep -F -- 'withNodeJs = false;' "$neovimModule"
  grep -F -- 'withPython3 = false;' "$neovimModule"
  grep -F -- 'withRuby = false;' "$neovimModule"
  ! grep -E -- '^[[:space:]]*(plugins|extraConfig|extraLuaConfig)[[:space:]]*=' "$neovimModule"

  touch "$out"
''
