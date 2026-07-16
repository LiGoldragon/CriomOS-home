{ pkgs, ... }:
pkgs.runCommand "noctalia-location-policy" { } ''
  set -eu

  module=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.gnugrep}/bin/grep -F 'location.autoLocate = false;' "$module"
  ${pkgs.gnugrep}/bin/grep -F 'clearNoctaliaIpLocation' "$module"
  ${pkgs.gnugrep}/bin/grep -F 'rm -f "$HOME/.cache/noctalia/location.json"' "$module"

  touch "$out"
''
