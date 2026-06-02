{ pkgs, ... }:

let
  playwrightCli = pkgs.callPackage ../../packages/playwright-cli { };
in
pkgs.runCommand "playwright-cli-starts"
  {
    nativeBuildInputs = [ playwrightCli ];
  }
  ''
    set -eu

    command -v playwright-cli
    playwright-cli --help >/dev/null

    touch "$out"
  ''
