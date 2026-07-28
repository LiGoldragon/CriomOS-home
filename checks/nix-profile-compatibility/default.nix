{ pkgs }:
let
  compatibility = pkgs.callPackage ../../packages/nix-profile-compatibility { };
  baseModule = builtins.readFile ../../modules/home/base.nix;
in
assert pkgs.lib.hasInfix ''entryBefore [ "installPackages" ]'' baseModule;
assert pkgs.lib.hasInfix "criomos-ensure-nix-profile-link" baseModule;
pkgs.runCommand "nix-profile-compatibility"
  {
    nativeBuildInputs = [
      compatibility
      pkgs.coreutils
      pkgs.findutils
    ];
  }
  ''
    set -eu

    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$HOME/.local/state"
    nix_state="$XDG_STATE_HOME/nix"
    profile="$nix_state/profile"
    managed="$nix_state/profiles/profile"
    migrations="$XDG_STATE_HOME/criomos/nix-profile-migrations"

    mkdir -p "$managed/bin"
    touch "$managed/bin/managed-tool"

    criomos-ensure-nix-profile-link
    test -L "$profile"
    test "$(readlink "$profile")" = profiles/profile
    test -e "$profile/bin/managed-tool"

    profile_inode="$(stat -c %i "$profile")"
    criomos-ensure-nix-profile-link
    test "$(stat -c %i "$profile")" = "$profile_inode"
    test ! -e "$migrations"

    unlink "$profile"
    mkdir -p "$profile/share/emacs/native-lisp"
    touch "$profile/share/emacs/native-lisp/preserved"
    criomos-ensure-nix-profile-link
    test -L "$profile"
    test "$(readlink "$profile")" = profiles/profile
    directory_backup="$(find "$migrations" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    test -n "$directory_backup"
    test -e "$directory_backup/share/emacs/native-lisp/preserved"

    unlink "$profile"
    ln -s unexpected-target "$profile"
    criomos-ensure-nix-profile-link
    test "$(readlink "$profile")" = profiles/profile
    symlink_backup="$(find "$migrations" -mindepth 1 -maxdepth 1 -type l -print -quit)"
    test -n "$symlink_backup"
    test "$(readlink "$symlink_backup")" = unexpected-target

    touch "$out"
  ''
