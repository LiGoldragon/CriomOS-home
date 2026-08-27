{ pkgs, ... }:
let
  fakeRawCodex = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf '%s\n' "$@" >> "$CODEX_GATE_CHILD_LOG"
      printf 'CODEX_HOME=%s\n' "$CODEX_HOME" >> "$CODEX_GATE_CHILD_LOG"
      printf 'raw:%s\\n' "$*"
    '';
  };
  gate = pkgs.callPackage ../../owned-agents/codex/desktop-gate.nix {
    codexCliPackage = fakeRawCodex;
  };
in
pkgs.runCommand "codex-desktop-gate-contract" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  export CODEX_GATE_CHILD_LOG="$TMPDIR/child.log"
  export CODEX_HOME="$TMPDIR/custom-codex-home"

  expect_allowed() {
    : > "$CODEX_GATE_CHILD_LOG"
    "$@" >/dev/null
    test -s "$CODEX_GATE_CHILD_LOG"
  }

  expect_rejected() {
    : > "$CODEX_GATE_CHILD_LOG"
    if "$@" >/dev/null 2>&1; then
      echo "unexpectedly allowed: $*" >&2
      exit 1
    fi
    test ! -s "$CODEX_GATE_CHILD_LOG"
  }

  expect_allowed ${gate}/bin/codex --version
  grep -Fx -- '--version' "$CODEX_GATE_CHILD_LOG"
  grep -Fx "CODEX_HOME=$CODEX_HOME" "$CODEX_GATE_CHILD_LOG"
  expect_allowed ${gate}/bin/codex app-server daemon version
  grep -Fx 'app-server' "$CODEX_GATE_CHILD_LOG"
  grep -Fx 'daemon' "$CODEX_GATE_CHILD_LOG"
  grep -Fx 'version' "$CODEX_GATE_CHILD_LOG"
  expect_allowed ${gate}/bin/codex help
  expect_rejected ${gate}/bin/codex -c features.code_mode_host=true app-server --analytics-default-enabled
  expect_rejected ${gate}/bin/codex app-server --remote-control --listen unix://
  expect_rejected ${gate}/bin/codex app-server daemon start
  expect_rejected ${gate}/bin/codex app-server proxy
  expect_rejected ${gate}/bin/codex unknown-command
  touch "$out"
''
