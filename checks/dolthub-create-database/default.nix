{ pkgs, ... }:
let
  command = pkgs.callPackage ../../packages/dolthub-create-database { };
in
pkgs.runCommand "dolthub-create-database-check" {
  nativeBuildInputs = [ command pkgs.gnugrep ];
} ''
  set -eu

  dolthub-create-database --help | grep -F -- '--owner OWNER'
  dolthub-create-database --help | grep -F -- '--gopass-entry PATH'

  if dolthub-create-database --owner 'bad/name' --database beads --visibility private; then
    echo 'invalid owner unexpectedly passed validation' >&2
    exit 1
  fi

  if dolthub-create-database --owner owner --database beads --visibility shared; then
    echo 'invalid visibility unexpectedly passed validation' >&2
    exit 1
  fi

  grep -F -- '--variable token@-' "${command}/bin/dolthub-create-database"
  grep -F -- '--expand-header' "${command}/bin/dolthub-create-database"
  grep -F -- 'https://www.dolthub.com/api/v1alpha1/database' "${command}/bin/dolthub-create-database"
  if grep -F -- 'Bearer' "${command}/bin/dolthub-create-database"; then
    echo 'Bearer authentication must not be present' >&2
    exit 1
  fi

  touch "$out"
''
