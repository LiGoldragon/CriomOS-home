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
    command -v playwright-chrome
    playwright-cli --help >/dev/null
    PLAYWRIGHT_MCP_EXTENSION_TOKEN=check-token playwright-chrome --help >/dev/null

    touch "$out"
  ''
