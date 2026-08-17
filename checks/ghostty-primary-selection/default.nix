{ pkgs, ... }:

let
  minProfile = builtins.readFile ../../modules/home/profiles/min/default.nix;
in
assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix "dconf.settings.\"org/gnome/desktop/interface\".gtk-enable-primary-paste = true;" minProfile)
  "The minimum desktop profile must retain GTK primary-selection paste for Ghostty";
pkgs.runCommand "ghostty-primary-selection" { } ''
  touch "$out"
''
