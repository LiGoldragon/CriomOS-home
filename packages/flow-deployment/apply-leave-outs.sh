#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf '%s\n' 'Usage: apply-leave-outs FLOW_META QUERY_FILE' >&2
  exit 2
fi
flow_meta=$1
query_file=$2
while IFS= read -r query; do
  if ! reply=$("$flow_meta" "$query"); then
    printf '%s\n' 'Flow leave-out configuration command failed' >&2
    exit 1
  fi
  if [[ $reply != Configured ]]; then
    printf 'Flow leave-out configuration refused: %s\n' "$reply" >&2
    exit 1
  fi
  printf '%s\n' "$reply"
done < "$query_file"
