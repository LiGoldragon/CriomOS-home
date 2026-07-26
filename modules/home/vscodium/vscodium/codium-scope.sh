#!/usr/bin/env bash
set -euf

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
valid_absolute_path "$state_dir" && canonical_existing_path "$state_dir" && [ -d "$state_dir" ] || path_error state
[ "$#" -ge 1 ] || path_error session
session_dir="$1"
shift
valid_absolute_path "$session_dir" && direct_child_of "$state_dir" "$session_dir" \
  && [[ "${session_dir##*/}" =~ ^session[.][A-Za-z0-9]{8}$ ]] \
  && canonical_existing_path "$session_dir" && [ -d "$session_dir" ] || path_error session
codium="${CRIOMOS_VSCODIUM_CODIUM:-@CODIUM@}"
case "$codium" in
  /*) [ -x "$codium" ] || exit 127 ;;
  *) exit 127 ;;
esac
started="$session_dir/started"
completed="$session_dir/completed"
tmp="$started.tmp.$$"
printf 'started\n' > "$tmp"
@COREUTILS@/bin/mv -f "$tmp" "$started"
set +e
"$codium" "$@"
status=$?
set -e
tmp="$completed.tmp.$$"
printf '%s\n' "$status" > "$tmp"
@COREUTILS@/bin/mv -f "$tmp" "$completed"
exit "$status"
