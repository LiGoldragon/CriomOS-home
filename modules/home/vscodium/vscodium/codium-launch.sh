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
if [ "${XDG_STATE_HOME+x}" = x ]; then xdg_state_home="$XDG_STATE_HOME"; valid_absolute_path "$xdg_state_home" || path_error XDG_STATE_HOME; fi
if [ "${CRIOMOS_VSCODIUM_STATE_DIR+x}" = x ]; then state_dir="$CRIOMOS_VSCODIUM_STATE_DIR"
elif [ "${XDG_STATE_HOME+x}" = x ]; then state_dir="$xdg_state_home/criomos/vscodium-claude"
else valid_absolute_path "$home_dir" || path_error HOME; state_dir="$home_dir/.local/state/criomos/vscodium-claude"; fi
if [ "${CRIOMOS_VSCODIUM_LOCK_FILE+x}" = x ]; then lock_file="$CRIOMOS_VSCODIUM_LOCK_FILE"
else lock_file="$state_dir/lifecycle.lock"; fi
valid_absolute_path "$state_dir" && canonical_existing_path "$state_dir" || path_error state
valid_absolute_path "$lock_file" && direct_child_of "$state_dir" "$lock_file" && canonical_existing_path "$lock_file" || path_error lock
codium="${CRIOMOS_VSCODIUM_CODIUM:-@CODIUM@}"
case "$codium" in
  /*) [ -x "$codium" ] || exit 127 ;;
  *) exit 127 ;;
esac

# These are Codium's terminal or state-management modes from `codium --help`.
# They must retain its synchronous CLI contract, including its exact output and
# exit status. GUI/file-opening modes use the short-lived supervisor below.
terminal_mode=0
for arg in "$@"; do
  case "$arg" in
    -h|--help|-v|--version|-s|--status|--list-extensions|--show-versions|--category|--install-extension|--install-extension=*|--uninstall-extension|--uninstall-extension=*|--update-extensions|--enable-proposed-api|--enable-proposed-api=*|--pre-release|--force|--add-mcp|--add-mcp=*|--sync|--sync=*|--locate-shell-integration-path|--locate-shell-integration-path=*|--telemetry|-w|--wait|--verbose)
      terminal_mode=1
      ;;
  esac
done
@COREUTILS@/bin/mkdir -p "$state_dir"
[ -d "$state_dir" ] && canonical_existing_path "$state_dir" || path_error state
canonical_existing_path "$lock_file" || path_error lock
exec 9>"$lock_file"
if @FLOCK@ -xn 9; then
  CRIOMOS_VSCODIUM_LOCK_HELD=1 @LIFECYCLE@ --prepare-launch
elif @FLOCK@ -sn 9; then
  : # A live supervisor protects mutable extension state with its SH lease.
else
  printf '%s\n' 'criomos-codium: lifecycle reconcile in progress; launch deferred' >&2
  exit 0
fi
@FLOCK@ -s 9
if [ "$terminal_mode" -eq 1 ]; then
  set +e
  "$codium" "$@"
  codium_status=$?
  set -e
  exit "$codium_status"
fi
session_dir="$(@COREUTILS@/bin/mktemp -d "$state_dir/session.XXXXXXXX")"
token="${session_dir##*/}"
valid_session() {
  valid_absolute_path "$session_dir" && direct_child_of "$state_dir" "$session_dir" \
    && [[ "$token" =~ ^session[.][A-Za-z0-9]{8}$ ]] && canonical_existing_path "$session_dir" \
    && [ -d "$session_dir" ] && [ ! -L "$session_dir" ] || return 1
  [ "$(@READLINK@ -f "$session_dir" 2>/dev/null || true)" = "$(@READLINK@ -f "$state_dir")/$token" ]
}
cleanup_unstarted() {
  valid_session || return 0
  @COREUTILS@/bin/rm -f "$session_dir/started" "$session_dir/ready" "$session_dir/status" "$session_dir/consumed"
  @COREUTILS@/bin/rmdir "$session_dir" 2>/dev/null || true
}
@SUPERVISOR@ "$session_dir" "$token" "$@" & supervisor_pid=$!
trap 'kill "$supervisor_pid" 2>/dev/null || true; cleanup_unstarted' ERR INT TERM HUP
attempts=0
while :; do
  valid_session || { printf '%s\n' 'criomos-codium: supervisor session vanished' >&2; exit 1; }
  if [ -f "$session_dir/ready" ] && [ ! -L "$session_dir/ready" ] \
    && [ "$(<"$session_dir/ready")" = "$token ready" ]; then break; fi
  if [ -f "$session_dir/status" ] && [ ! -L "$session_dir/status" ]; then
    status_record="$(<"$session_dir/status")"
    case "$status_record" in "$token "[1-9]*|"$token "[1-9][0-9]*) printf '%s\n' 'criomos-codium: command failed to start' >&2; exit 1;; esac
  fi
  attempts=$((attempts + 1)); [ "$attempts" -lt 100 ] || { printf '%s\n' 'criomos-codium: supervisor did not acknowledge startup' >&2; exit 1; }
  @SLEEP@ 0.05
done
printf '%s\n' "$token consumed" > "$session_dir/consumed.tmp.$$"
@COREUTILS@/bin/mv -f "$session_dir/consumed.tmp.$$" "$session_dir/consumed"
trap - ERR INT TERM HUP
exec 9>&-
exit 0
