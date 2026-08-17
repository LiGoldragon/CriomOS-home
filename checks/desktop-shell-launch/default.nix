{ pkgs, ... }:
let
  niri = builtins.readFile ../../modules/home/profiles/min/niri.nix;
  chroma = builtins.readFile ../../modules/home/profiles/min/chroma.nix;
in
assert pkgs.lib.hasInfix
  "noctaliaShell = inputs.noctalia.packages.\${pkgs.stdenv.hostPlatform.system}.default;"
  niri;
assert pkgs.lib.hasInfix ''{ command = [ "''${noctaliaShell}/bin/noctalia" ]; }'' niri;
assert !(pkgs.lib.hasInfix ''{ command = [ "noctalia-shell" ]; }'' niri);
assert pkgs.lib.hasInfix "shell-integration = none" chroma;
pkgs.runCommand "desktop-shell-launch" { } ''
  touch "$out"
''
