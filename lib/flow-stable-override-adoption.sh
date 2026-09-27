#!/usr/bin/env bash
set -euo pipefail

expected=$1
target=$2
parent=$(dirname "$target")
flock_command=${FLOW_STABLE_OVERRIDE_FLOCK:-flock}

fail() {
  printf 'flow stable override adoption refused: path=%s reason=%s\n' "$target" "$1" >&2
  exit 1
}

if [ ! -d "$parent" ]; then
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    exit 0
  fi
  fail parent-not-directory
fi

# Serialize cooperating Home activations, then validate again after the move.
# A moved file is deleted only after its bytes have been rechecked.
exec 9>"$parent/.flow-nexus-override-adoption.lock"
"$flock_command" -x 9

if [ ! -e "$target" ] && [ ! -L "$target" ]; then
  exit 0
fi

if [ -L "$target" ]; then
  fail symlink
fi
if [ ! -f "$target" ]; then
  fail "non-regular-$(stat -c '%F' -- "$target" 2>/dev/null || printf unknown)"
fi
if ! cmp -s -- "$expected" "$target"; then
  fail byte-mismatch
fi

backup=$(mktemp "$parent/.flow-nexus-override-adoption.XXXXXX")
rm -- "$backup"
if ! mv -- "$target" "$backup"; then
  fail move-failed
fi

if [ -L "$backup" ] || [ ! -f "$backup" ] || ! cmp -s -- "$expected" "$backup"; then
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    mv -- "$backup" "$target" || fail restore-failed
  fi
  fail changed-during-adoption
fi

rm -- "$backup"
