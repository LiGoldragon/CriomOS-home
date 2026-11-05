{ pkgs, ... }:
pkgs.runCommand "flow-initialize-trap" {
  nativeBuildInputs = [ pkgs.bash pkgs.gnugrep ];
} ''
  grep -F 'configure_one() (' ${../../packages/flow-deployment/default.nix}
  cat > regression.sh <<'SH'
  set -euo pipefail
  configure_one() (
    local child
    sleep 60 &
    child=$!
    printf '%s\n' "$child" > child.pid
    trap 'kill "$child" 2>/dev/null || true' EXIT
    false
  )
  configure_one
  SH
  if bash regression.sh 2> error; then
    echo 'failure path unexpectedly succeeded' >&2
    exit 1
  fi
  if grep -q 'unbound variable' error; then cat error >&2; exit 1; fi
  child=$(cat child.pid)
  for _attempt in $(seq 1 100); do
    if ! kill -0 "$child" 2>/dev/null; then break; fi
    sleep 0.01
  done
  ! kill -0 "$child" 2>/dev/null
  touch "$out"
''
