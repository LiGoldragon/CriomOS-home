{ pkgs, ... }:
let
  fakeRawCodex = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf '%s\n' "$@" >> "$CODEX_GATE_CHILD_LOG"
      printf 'CODEX_HOME=%s\n' "$CODEX_HOME" >> "$CODEX_GATE_CHILD_LOG"
      if test "$#" = 4 && test "$1" = app-server && test "$2" = proxy && test "$3" = --sock; then
        test -S "$4"
        cat
        exit 0
      fi
      printf 'raw:%s\\n' "$*"
    '';
  };
  gate = pkgs.callPackage ../../owned-agents/codex/desktop-gate.nix {
    codexCliPackage = fakeRawCodex;
  };
in
pkgs.runCommand "codex-desktop-gate-contract" {
  nativeBuildInputs = [
    pkgs.coreutils
    pkgs.python3
  ];
} ''
  set -eu
  export CODEX_GATE_CHILD_LOG="$TMPDIR/child.log"
  export CODEX_HOME="$TMPDIR/custom-codex-home"
  socket="$CODEX_HOME/app-server-control/app-server-control.sock"
  mkdir -p "$(dirname "$socket")"

  python3 - "$socket" <<'PY' &
import os
import socket
import sys
import time

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(sys.argv[1])
os.chmod(sys.argv[1], 0o600)
sock.listen()
time.sleep(300)
PY
  listener_pid=$!
  trap 'kill "$listener_pid" 2>/dev/null || true' EXIT
  while ! test -S "$socket"; do sleep 0.1; done
  test "$(stat -c %a "$socket")" = 600

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

  expect_proxy() {
    : > "$CODEX_GATE_CHILD_LOG"
    payload='{"method":"notifications/event","params":{"type":"mcp","message":"transparent"}}'
    printf '%s\n' "$payload" | ${gate}/bin/codex app-server > "$TMPDIR/proxy-output"
    cmp <(printf '%s\n' "$payload") "$TMPDIR/proxy-output"
    test "$(cat "$CODEX_GATE_CHILD_LOG")" = "$({
      printf '%s\n' \
        app-server \
        proxy \
        --sock \
        "$socket" \
        "CODEX_HOME=$CODEX_HOME"
    })"
  }

  expect_allowed ${gate}/bin/codex --version
  grep -Fx -- '--version' "$CODEX_GATE_CHILD_LOG"
  grep -Fx "CODEX_HOME=$CODEX_HOME" "$CODEX_GATE_CHILD_LOG"
  expect_allowed ${gate}/bin/codex app-server daemon version
  grep -Fx 'app-server' "$CODEX_GATE_CHILD_LOG"
  grep -Fx 'daemon' "$CODEX_GATE_CHILD_LOG"
  grep -Fx 'version' "$CODEX_GATE_CHILD_LOG"
  expect_allowed ${gate}/bin/codex help
  expect_proxy
  expect_rejected ${gate}/bin/codex -c features.code_mode_host=true app-server --analytics-default-enabled
  expect_rejected ${gate}/bin/codex app-server --remote-control --listen unix://
  expect_rejected ${gate}/bin/codex app-server daemon start
  expect_rejected ${gate}/bin/codex app-server proxy
  expect_rejected ${gate}/bin/codex unknown-command
  kill "$listener_pid"
  wait "$listener_pid" || true
  rm "$socket"
  expect_rejected ${gate}/bin/codex app-server
  test ! -s "$CODEX_GATE_CHILD_LOG"
  touch "$out"
''
