{ inputs, pkgs, ... }:
let
  messenger = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
in pkgs.writeShellApplication {
  name = "activate-messenger-clj";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    if [ "$#" -ne 2 ]; then echo "usage: activate-messenger-clj HOME-DIRECTORY PREVIOUS-PACKAGE" >&2; exit 2; fi
    home_dir="$1"
    previous="$2"
    case "$previous" in /nix/store/*) ;; *) echo "previous package must be immutable" >&2; exit 2 ;; esac
    bin="$home_dir/.local/bin"
    test -d "$bin"
    commands=(messenger-clj hm-send hm-send-abrupt hm-list hm-register hm-repair hm-deregister hm-rebind hm-move hm-retire hm-heartbeat-state)
    # Validate the whole owned set before replacing even one link.
    for command in "''${commands[@]}"; do
      test -x "${messenger}/bin/$command"
      test -x "$previous/bin/$command"
      target="$bin/$command"
      if [ -e "$target" ] || [ -L "$target" ]; then
        test -L "$target" || { echo "foreign messenger file: $target" >&2; exit 1; }
        actual=$(readlink -f "$target")
        old=$(readlink -f "$previous/bin/$command")
        new=$(readlink -f "${messenger}/bin/$command")
        [ "$actual" = "$old" ] || [ "$actual" = "$new" ] || { echo "foreign messenger link: $target" >&2; exit 1; }
      fi
    done
    temporary=$(mktemp -d "$bin/.messenger-activation.XXXXXX")
    trap 'rm -f "$temporary/link"; rmdir "$temporary"' EXIT
    for command in "''${commands[@]}"; do
      ln -s "${messenger}/bin/$command" "$temporary/link"
      mv -T "$temporary/link" "$bin/$command"
      test "$(readlink -f "$bin/$command")" = "$(readlink -f "${messenger}/bin/$command")"
    done
    printf '%s\n' '${messenger}'
  '';
}
