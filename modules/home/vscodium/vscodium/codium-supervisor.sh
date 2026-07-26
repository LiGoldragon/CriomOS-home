#!/usr/bin/env bash
set -euf
export LC_ALL=C
umask 077

path_error() { printf 'criomos-codium: invalid %s path\n' "$1" >&2; exit 64; }
valid_absolute_path() {
  [ -n "$1" ] || return 1
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in *$'\n'*|*$'\r'*|*[[:cntrl:]]*|*'//'*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
}
canonical_existing_path() {
  path_probe="$1"
  while [ ! -e "$path_probe" ] && [ ! -L "$path_probe" ]; do path_probe="${path_probe%/*}"; done
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
  xdg_state_home="$XDG_STATE_HOME"; valid_absolute_path "$xdg_state_home" || path_error XDG_STATE_HOME
fi
if [ "${CRIOMOS_VSCODIUM_STATE_DIR+x}" = x ]; then state_dir="$CRIOMOS_VSCODIUM_STATE_DIR"
elif [ "${XDG_STATE_HOME+x}" = x ]; then state_dir="$xdg_state_home/criomos/vscodium-claude"
else valid_absolute_path "$home_dir" || path_error HOME; state_dir="$home_dir/.local/state/criomos/vscodium-claude"; fi
if [ "${CRIOMOS_VSCODIUM_LOCK_FILE+x}" = x ]; then lock_file="$CRIOMOS_VSCODIUM_LOCK_FILE"
else lock_file="$state_dir/lifecycle.lock"; fi
valid_absolute_path "$state_dir" && canonical_existing_path "$state_dir" && [ -d "$state_dir" ] || path_error state
valid_absolute_path "$lock_file" && direct_child_of "$state_dir" "$lock_file" && canonical_existing_path "$lock_file" || path_error lock
[ "$#" -ge 2 ] || path_error session
session_dir="$1"; token="$2"; shift 2
valid_session() {
  valid_absolute_path "$session_dir" && direct_child_of "$state_dir" "$session_dir" \
    && [ "${session_dir##*/}" = "$token" ] && [[ "$token" =~ ^session[.][A-Za-z0-9]{8}$ ]] \
    && canonical_existing_path "$session_dir" && [ -d "$session_dir" ] && [ ! -L "$session_dir" ] || return 1
  canonical_state="$(@READLINK@ -f "$state_dir" 2>/dev/null || true)"
  canonical_session="$(@READLINK@ -f "$session_dir" 2>/dev/null || true)"
  [ "$canonical_session" = "$canonical_state/$token" ]
}
valid_session || path_error session
codium="${CRIOMOS_VSCODIUM_CODIUM:-@CODIUM@}"
case "$codium" in /*) [ -x "$codium" ] || exit 127;; *) exit 127;; esac
write_state() {
  state_name="$1" state_value="$2" state_tmp="$session_dir/$state_name.tmp.$$"
  valid_session || return 1
  printf '%s\n' "$token $state_value" > "$state_tmp"
  @COREUTILS@/bin/mv -f "$state_tmp" "$session_dir/$state_name"
}
cleanup() {
  valid_session || return 0
  @COREUTILS@/bin/rm -f "$session_dir/started" "$session_dir/ready" "$session_dir/status" "$session_dir/consumed"
  @COREUTILS@/bin/rmdir "$session_dir" 2>/dev/null || true
}
child_pid=""
forward_signal() {
  signal="$1"
  trap - INT TERM HUP
  if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
    kill -"$signal" "$child_pid" 2>/dev/null || true
    set +e
    wait "$child_pid"
    child_status=$?
    set -e
    write_state status "$child_status" || true
  fi
  cleanup
  exit 143
}
trap 'forward_signal HUP' HUP
trap 'forward_signal INT' INT
trap 'forward_signal TERM' TERM
# The supported Codium command is foreground/synchronous. Keep its session,
# process group, cgroup, cwd, environment, and argv unchanged; in particular,
# do not use a manager service or `setsid` while fixing a cgroup-correlated bug.
write_state started started
write_state ready ready
set +e
"$codium" "$@" & child_pid=$!
wait "$child_pid"; child_status=$?
set -e
write_state status "$child_status"
# Preserve the authenticated result long enough for a fast CLI launcher to
# acknowledge it. A killed launcher leaves only its own fresh session behind.
attempts=0
while :; do
  valid_session || exit 0
  if [ -f "$session_dir/consumed" ] && [ ! -L "$session_dir/consumed" ] \
    && [ "$(<"$session_dir/consumed")" = "$token consumed" ]; then break; fi
  attempts=$((attempts + 1)); [ "$attempts" -lt 100 ] || break
  @SLEEP@ 0.05
done
cleanup
exit "$child_status"
