{ pkgs, ... }:
let
  playwrightCli = pkgs.callPackage ../../packages/playwright-cli { };
  fakeGopass = pkgs.writeShellScriptBin "gopass" ''
    printf '%s\n' "$@" > "$FIXTURE_GOPASS_LOG"
    case "$FIXTURE_GOPASS_MODE" in
      missing) exit 11 ;;
      unreadable) printf '%s\n' fixture-secret-must-stay-private >&2; exit 1 ;;
      empty) exit 0 ;;
      success) printf '%s\n' fixture-secret-must-stay-private ;;
      *) exit 2 ;;
    esac
  '';
  fakeNode = pkgs.writeShellScriptBin "node" ''
    printf '%s\n' invoked > "$FIXTURE_CLI_LOG"
    test "$PLAYWRIGHT_MCP_EXTENSION_TOKEN" = "$FIXTURE_EXPECTED_TOKEN"
  '';
  fixturePkgs = pkgs // {
    gopass = fakeGopass;
    nodejs = fakeNode;
    buildNpmPackage = attributes: pkgs.runCommand "playwright-wrapper-fixture" {
      inherit (attributes) nativeBuildInputs;
    } ''
      mkdir node_modules
      touch package.json package-lock.json
      ${attributes.installPhase}
    '';
  };
  configuredEntry = ''fixture's entry/$(touch "$FIXTURE_INJECTION")'';
  fixture = entry: import ../../packages/playwright-cli {
    pkgs = fixturePkgs;
    extensionTokenEntry = entry;
  };
  configured = fixture configuredEntry;
  unconfigured = fixture null;
  homeSource = builtins.readFile ../../modules/home/profiles/min/default.nix;
in
assert pkgs.lib.hasInfix ''default = "playwright.dev/mcp-extension-token";'' homeSource;
assert pkgs.lib.hasInfix "extensionTokenEntry = config.criomosHome.playwrightChrome.secretEntry;" homeSource;
pkgs.runCommand "playwright-cli-secret-guard"
  { nativeBuildInputs = [ playwrightCli ]; }
  ''
    set -eu
    playwright-cli --help >/dev/null
    export FIXTURE_GOPASS_LOG="$TMPDIR/gopass"
    export FIXTURE_CLI_LOG="$TMPDIR/cli"
    export FIXTURE_DISCOVERY_LOG="$TMPDIR/discovery"
    export FIXTURE_INJECTION="$TMPDIR/injection"
    export FIXTURE_EXPECTED_TOKEN=fixture-secret-must-stay-private
    unset PLAYWRIGHT_MCP_EXTENSION_TOKEN PLAYWRIGHT_MCP_EXECUTABLE_PATH
    command() {
      if [ "''${1:-}" = -v ]; then
        case "''${2:-}" in
          google-chrome|chromium) printf '%s\n' discovery >> "$FIXTURE_DISCOVERY_LOG" ;;
        esac
      fi
      builtin command "$@"
    }
    export -f command
    reset_logs() {
      rm -f "$FIXTURE_GOPASS_LOG" "$FIXTURE_CLI_LOG" "$FIXTURE_DISCOVERY_LOG"
    }
    assert_no_browser() {
      test ! -e "$FIXTURE_CLI_LOG"
      test ! -e "$FIXTURE_DISCOVERY_LOG"
      test ! -e "$FIXTURE_INJECTION"
    }
    assert_no_token_output() {
      if grep -F -e fixture-secret-must-stay-private -e fixture-env-must-stay-private "$TMPDIR/output"; then
        exit 1
      fi
    }
    for mode in missing unreadable empty; do
      reset_logs
      export FIXTURE_GOPASS_MODE="$mode"
      if ${configured}/bin/playwright-chrome Fixture > "$TMPDIR/output" 2>&1; then exit 1; fi
      printf '%s\n' show -o ${pkgs.lib.escapeShellArg configuredEntry} > "$TMPDIR/expected"
      diff -u "$TMPDIR/expected" "$FIXTURE_GOPASS_LOG"
      grep -F -- ${pkgs.lib.escapeShellArg configuredEntry} "$TMPDIR/output" >/dev/null
      assert_no_browser
      assert_no_token_output
    done
    reset_logs
    if ${unconfigured}/bin/playwright-chrome Fixture > "$TMPDIR/output" 2>&1; then exit 1; fi
    grep -F 'secret entry is not configured' "$TMPDIR/output" >/dev/null
    test ! -e "$FIXTURE_GOPASS_LOG"
    assert_no_browser
    assert_no_token_output
    reset_logs
    export PLAYWRIGHT_MCP_EXTENSION_TOKEN=
    if ${configured}/bin/playwright-chrome Fixture > "$TMPDIR/output" 2>&1; then exit 1; fi
    grep -F PLAYWRIGHT_MCP_EXTENSION_TOKEN "$TMPDIR/output" >/dev/null
    test ! -e "$FIXTURE_GOPASS_LOG"
    assert_no_browser
    assert_no_token_output
    reset_logs
    unset PLAYWRIGHT_MCP_EXTENSION_TOKEN
    export FIXTURE_GOPASS_MODE=success
    ${configured}/bin/playwright-chrome Fixture > "$TMPDIR/output" 2>&1
    test -e "$FIXTURE_GOPASS_LOG"
    test -e "$FIXTURE_CLI_LOG"
    test -e "$FIXTURE_DISCOVERY_LOG"
    test ! -e "$FIXTURE_INJECTION"
    assert_no_token_output
    reset_logs
    export PLAYWRIGHT_MCP_EXTENSION_TOKEN=fixture-env-must-stay-private
    export FIXTURE_EXPECTED_TOKEN=fixture-env-must-stay-private
    ${configured}/bin/playwright-chrome Fixture > "$TMPDIR/output" 2>&1
    test ! -e "$FIXTURE_GOPASS_LOG"
    test -e "$FIXTURE_CLI_LOG"
    test -e "$FIXTURE_DISCOVERY_LOG"
    test ! -e "$FIXTURE_INJECTION"
    assert_no_token_output
    touch "$out"
  ''
