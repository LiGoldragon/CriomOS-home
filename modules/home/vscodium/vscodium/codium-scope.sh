#!/usr/bin/env bash
set -euf

session_dir="$1"
shift
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
