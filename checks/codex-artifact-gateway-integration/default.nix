{ pkgs, inputs, ... }:
let
  gateway = pkgs.callPackage ../../packages/codex-artifact-gateway { };
in
pkgs.runCommand "codex-artifact-gateway-integration"
  {
    nativeBuildInputs = [
      pkgs.bun
      pkgs.coreutils
      pkgs.python3
    ];
  }
  ''
    set -eu
    socket="$TMPDIR/broker.sock"
    fifo="$TMPDIR/ready"
    mkfifo "$fifo"
    timeout 30s bun ${./broker_fixture.ts} \
      ${inputs.plannotator-capability} "$socket" > "$fifo" &
    broker_pid=$!
    trap 'kill "$broker_pid" 2>/dev/null || true; wait "$broker_pid" 2>/dev/null || true' EXIT
    IFS= read -r capability < "$fifo"
    PYTHONDONTWRITEBYTECODE=1 timeout 30s python3 ${./gateway_integration.py} \
      ${gateway}/libexec/codex-artifact-gateway/gateway.py "$socket" "$capability"
    touch "$out"
  ''
