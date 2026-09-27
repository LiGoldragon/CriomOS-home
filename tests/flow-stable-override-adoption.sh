#!/usr/bin/env bash
set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
expected="$root/expected"
target="$root/home/.config/systemd/user/flow-nexus.service.d/override.conf"
guard="$(cd "$(dirname "$0")/.." && pwd)/lib/flow-stable-override-adoption.sh"
expected_fixture="$(cd "$(dirname "$0")" && pwd)/fixtures/flow-nexus-live-override.conf"
managed_source="$(cd "$(dirname "$0")/.." && pwd)/lib/flow-nexus-stable-override.conf"
mkdir -p "$(dirname "$target")"
cmp -s -- "$expected_fixture" "$managed_source"
cp -- "$expected_fixture" "$expected"

expect_success() { "$guard" "$expected" "$target"; }
expect_failure_unchanged() {
  before=$(sha256sum "$target" | cut -d' ' -f1)
  if "$guard" "$expected" "$target"; then
    echo "expected guard failure for $1" >&2
    exit 1
  fi
  after=$(sha256sum "$target" | cut -d' ' -f1)
  [ "$before" = "$after" ] || { echo "guard changed rejected $1" >&2; exit 1; }
}

# Absent is accepted.
expect_success

# Exact regular is adopted; its pre-link rerun is absent and succeeds.
cp "$expected" "$target"
expect_success
[ ! -e "$target" ] && [ ! -L "$target" ]
expect_success

printf 'x' > "$target"
expect_failure_unchanged one-byte-difference
cat "$expected" > "$target"
printf 'Environment=EXTRA=1\n' >> "$target"
expect_failure_unchanged extra-directive
rm "$target"
ln -s "$expected" "$target"
if "$guard" "$expected" "$target"; then
  echo 'expected symlink rejection' >&2
  exit 1
fi
[ -L "$target" ]
rm "$target"
ln -s "$root/missing" "$target"
if "$guard" "$expected" "$target"; then
  echo 'expected dangling symlink rejection' >&2
  exit 1
fi
[ -L "$target" ]
rm "$target"
mkdir "$target"
if "$guard" "$expected" "$target"; then
  echo 'expected directory rejection' >&2
  exit 1
fi
[ -d "$target" ]
rmdir "$target"
mkfifo "$target"
if "$guard" "$expected" "$target"; then
  echo 'expected fifo rejection' >&2
  exit 1
fi
[ -p "$target" ]
