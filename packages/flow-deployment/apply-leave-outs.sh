#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf '%s\n' 'Usage: apply-leave-outs FLOW_META QUERY_FILE' >&2
  exit 2
fi
flow_meta=$1
query_file=$2
mapfile -t queries < "$query_file"
if [[ ${#queries[@]} -ne 1 || -z ${queries[0]} ]]; then
  printf '%s\n' 'Expected one whole Flow leave-out declaration' >&2
  exit 1
fi
if ! reply=$("$flow_meta" "${queries[0]}"); then
  printf '%s\n' 'Flow leave-out configuration command failed' >&2
  exit 1
fi
case "$reply" in
  Configured.Replaced|Configured.Unchanged) printf '%s\n' "$reply" ;;
  *) printf 'Flow leave-out configuration refused: %s\n' "$reply" >&2; exit 1 ;;
esac
