#!/usr/bin/env bash
set -euf
export LC_ALL=C

state_dir="${CRIOMOS_VSCODIUM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/criomos/vscodium-claude}"
lock_file="${CRIOMOS_VSCODIUM_LOCK_FILE:-$state_dir/lifecycle.lock}"
mkdir -p "$state_dir"
exec 9>"$lock_file"

# Never queue a GUI launch behind a mutation. An existing shared lease is safe
# to join; an exclusive activation/reconcile is not.
if @FLOCK@ -xn 9; then
  CRIOMOS_VSCODIUM_LOCK_HELD=1 @LIFECYCLE@ --prepare-launch
elif @FLOCK@ -sn 9; then
  : # Another live Codium scope already protects mutable extension state.
else
  printf '%s\n' 'criomos-codium: lifecycle reconcile in progress; launch deferred' >&2
  exit 0
fi

unit_id="$(@DATE@ +%s%N)-$$"
scope="criomos-vscodium-$unit_id.scope"
watcher="criomos-vscodium-lease-$unit_id.service"
session_dir="$(mktemp -d "$state_dir/session.XXXXXXXX")"
ready="$session_dir/ready"
cleanup() {
  @SYSTEMCTL@ --user stop "$watcher" "$scope" >/dev/null 2>&1 || true
  rm -f "$session_dir/ready" "$session_dir/consumed" "$session_dir/started" "$session_dir/completed"
  rmdir "$session_dir" 2>/dev/null || true
}
trap cleanup ERR INT TERM

@SYSTEMD_RUN@ --user --scope --collect --quiet --no-block --unit="$scope" @SCOPE_RUNNER@ "$session_dir" "$@"

# `--no-block` confirms the user manager accepted the unit but not that its
# command survived startup. Verify this exact scope before giving up EX.
attempts=0
while :; do
  active="$(@SYSTEMCTL@ --user show "$scope" --property=ActiveState --value 2>/dev/null || true)"
  completed="$(cat "$session_dir/completed" 2>/dev/null || true)"
  if [ -f "$session_dir/started" ] && [ "$(cat "$session_dir/started" 2>/dev/null || true)" = started ]; then
    if [ -n "$completed" ] && [ "$completed" != 0 ]; then
      printf '%s\n' 'criomos-codium: GUI command failed to start' >&2
      exit 1
    fi
    break
  fi
  case "$active" in
    active|activating|reloading)
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 100 ]; then
        printf '%s\n' 'criomos-codium: GUI scope did not acknowledge startup' >&2
        exit 1
      fi
      @SLEEP@ 0.05
      ;;
    inactive|failed|deactivating)
      printf '%s\n' 'criomos-codium: GUI scope failed to start' >&2
      exit 1
      ;;
    *)
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 100 ]; then
        printf '%s\n' 'criomos-codium: GUI scope did not appear' >&2
        exit 1
      fi
      @SLEEP@ 0.05
      ;;
  esac
done

# This is an atomic lock conversion on the same descriptor. The wrapper
# retains SH until the watcher independently holds SH and has published READY.
@FLOCK@ -s 9
@SYSTEMD_RUN@ --user --collect --quiet --no-block --unit="$watcher" \
  --property=Restart=on-failure --property=RestartSec=100ms \
  @LIFECYCLE@ --watch-scope "$scope" "$ready"

attempts=0
while [ ! -f "$ready" ] || [ "$(cat "$ready" 2>/dev/null || true)" != ready ]; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 100 ]; then
    printf '%s\n' 'criomos-codium: session lease watcher did not become ready' >&2
    exit 1
  fi
  @SLEEP@ 0.05
done
# The watcher keeps READY durable through a fast scope exit; acknowledge it
# atomically so the watcher can reclaim the per-launch directory.
: > "$session_dir/consumed"
trap - ERR INT TERM
exec 9>&-
exit 0
