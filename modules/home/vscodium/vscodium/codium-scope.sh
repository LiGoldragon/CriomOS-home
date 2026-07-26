#!/usr/bin/env bash
set -euf

session_dir="$1"
shift
started="$session_dir/started"
completed="$session_dir/completed"
tmp="$started.tmp.$$"
printf 'started\n' > "$tmp"
mv -f "$tmp" "$started"
set +e
@CODIUM@ "$@"
status=$?
set -e
tmp="$completed.tmp.$$"
printf '%s\n' "$status" > "$tmp"
mv -f "$tmp" "$completed"
exit "$status"
