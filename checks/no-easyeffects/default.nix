{ pkgs, ... }:

let
  inherit (pkgs) lib;
  maxProfile = builtins.readFile ../../modules/home/profiles/max/default.nix;
in
assert lib.assertMsg (
  !(lib.hasInfix "easyeffects" maxProfile)
) "EasyEffects must not be enabled or installed by the max home profile";

pkgs.runCommand "no-easyeffects-check" { } ''
  touch "$out"
''
