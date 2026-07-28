set -eu

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
nix_state="$state_home/nix"
profile="$nix_state/profile"
desired_target="profiles/profile"

if [ -L "$profile" ] && [ "$(readlink "$profile")" = "$desired_target" ]; then
  exit 0
fi

mkdir -p "$nix_state"
temporary="$nix_state/.profile.criomos-link.$$"
if [ -e "$temporary" ] || [ -L "$temporary" ]; then
  echo "temporary profile-link path already exists: $temporary" >&2
  exit 1
fi
ln -s "$desired_target" "$temporary"

if [ -e "$profile" ] || [ -L "$profile" ]; then
  migrations="$state_home/criomos/nix-profile-migrations"
  mkdir -p "$migrations"
  timestamp="$(date -u +%Y%m%dT%H%M%S.%N)"
  backup="$migrations/profile.$timestamp.$$"
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    echo "profile migration path already exists: $backup" >&2
    exit 1
  fi

  mv --exchange --no-copy -T "$temporary" "$profile"
  mv -T "$temporary" "$backup"
  echo "preserved prior Nix profile compatibility object at $backup"
else
  mv -T "$temporary" "$profile"
fi
