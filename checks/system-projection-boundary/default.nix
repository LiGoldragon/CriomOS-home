{ pkgs }:
pkgs.runCommand "system-projection-boundary" { } ''
  source=${../..}

  matches="$(
    find "$source" -type f -name '*.nix' \
      ! -path "$source/checks/system-projection-boundary/default.nix" \
      ! -path "$source/modules/home/profiles/min/dictation.nix" \
      -print0 \
      | xargs -0 --no-run-if-empty grep -nE '[l]ojix|LOJIX' || true
  )"

  if [ -n "$matches" ]; then
    printf '%s\n' "$matches" >&2
    echo "Home Nix sources must not retain an OS deployment edge" >&2
    exit 1
  fi

  if grep -nE '[l]ojix|LOJIX' "$source/flake.lock"; then
    echo "Home lock state must not retain an OS deployment edge" >&2
    exit 1
  fi

  touch "$out"
''
