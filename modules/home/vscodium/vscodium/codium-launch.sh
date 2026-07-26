#!/usr/bin/env bash
set -euf
export LC_ALL=C

path_error() { printf 'criomos-codium: invalid %s path\n' "$1" >&2; exit 64; }
valid_absolute_path() {
  [ -n "$1" ] || return 1
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in *$'\n'*|*$'\r'*|*[[:cntrl:]]*|*'//'*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
}
canonical_existing_path() {
  path_probe="$1"
  while [ ! -e "$path_probe" ] && [ ! -L "$path_probe" ]; do
    path_probe="${path_probe%/*}"
  done
  [ -n "$path_probe" ] || return 1
  [ "$path_probe" = "$1" ] || [ -d "$path_probe" ] || return 1
  [ "$(@READLINK@ -f "$path_probe" 2>/dev/null || true)" = "$path_probe" ]
}
direct_child_of() {
  parent="$1" child="$2"
  case "$child" in "$parent"/*) leaf="${child#"$parent"/}" ;; *) return 1 ;; esac
  [ -n "$leaf" ] && [[ "$leaf" != */* ]]
}
home_dir="${HOME:-}"
if [ "${XDG_STATE_HOME+x}" = x ]; then
  xdg_state_home="$XDG_STATE_HOME"
  valid_absolute_path "$xdg_state_home" || path_error XDG_STATE_HOME
fi
if [ "${CRIOMOS_VSCODIUM_STATE_DIR+x}" = x ]; then
  state_dir="$CRIOMOS_VSCODIUM_STATE_DIR"
elif [ "${XDG_STATE_HOME+x}" = x ]; then
  state_dir="$xdg_state_home/criomos/vscodium-claude"
else
  valid_absolute_path "$home_dir" || path_error HOME
  state_dir="$home_dir/.local/state/criomos/vscodium-claude"
fi
if [ "${CRIOMOS_VSCODIUM_LOCK_FILE+x}" = x ]; then
  lock_file="$CRIOMOS_VSCODIUM_LOCK_FILE"
else
  lock_file="$state_dir/lifecycle.lock"
fi
valid_absolute_path "$state_dir" && canonical_existing_path "$state_dir" || path_error state
valid_absolute_path "$lock_file" && direct_child_of "$state_dir" "$lock_file" \
  && canonical_existing_path "$lock_file" || path_error lock
systemctl="${CRIOMOS_VSCODIUM_SYSTEMCTL:-@SYSTEMCTL@}"
systemd_run="${CRIOMOS_VSCODIUM_SYSTEMD_RUN:-@SYSTEMD_RUN@}"
for runtime_command in "$systemctl" "$systemd_run"; do
  case "$runtime_command" in
    /*) [ -x "$runtime_command" ] || exit 127 ;;
    *) exit 127 ;;
  esac
done
@COREUTILS@/bin/mkdir -p "$state_dir"
[ -d "$state_dir" ] && canonical_existing_path "$state_dir" || path_error state
canonical_existing_path "$lock_file" || path_error lock
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
session_dir="$(@COREUTILS@/bin/mktemp -d "$state_dir/session.XXXXXXXX")"
ready="$session_dir/ready"
cleanup() {
  "$systemctl" --user stop "$watcher" "$scope" >/dev/null 2>&1 || true
  @COREUTILS@/bin/rm -f "$session_dir/ready" "$session_dir/consumed" "$session_dir/started" "$session_dir/completed"
  @COREUTILS@/bin/rmdir "$session_dir" 2>/dev/null || true
}
trap cleanup ERR INT TERM

"$systemd_run" --user --scope --collect --quiet --no-block --unit="$scope" @SCOPE_RUNNER@ "$session_dir" "$@"

# `--no-block` confirms the user manager accepted the unit but not that its
# command survived startup. Verify this exact scope before giving up EX.
attempts=0
while :; do
  active="$("$systemctl" --user show "$scope" --property=ActiveState --value 2>/dev/null || true)"
  completed="$(@COREUTILS@/bin/cat "$session_dir/completed" 2>/dev/null || true)"
  if [ -f "$session_dir/started" ] && [ "$(@COREUTILS@/bin/cat "$session_dir/started" 2>/dev/null || true)" = started ]; then
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
"$systemd_run" --user --collect --quiet --no-block --unit="$watcher" \
  --property=Restart=on-failure --property=RestartSec=100ms \
  @LIFECYCLE@ --watch-scope "$scope" "$ready"

attempts=0
while [ ! -f "$ready" ] || [ "$(@COREUTILS@/bin/cat "$ready" 2>/dev/null || true)" != ready ]; do
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
