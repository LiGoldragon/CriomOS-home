{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    # Desktop may inspect its bundled candidate and probe the already-owned
    # local daemon.  Its required bare app-server stdio endpoint is a
    # transparent client of that owner, never an owner lifecycle entry point.
    case "$#" in
      1)
        case "$1" in
          --version|-V|version|--help|-h|help)
            exec ${codexCliPackage}/bin/codex "$@"
            ;;
          app-server)
            codex_home="''${CODEX_HOME:-$HOME/.codex}"
            socket="$codex_home/app-server-control/app-server-control.sock"
            if ! test -S "$socket" || ! test -O "$socket" || test "$(stat -c %a "$socket")" != 600; then
              printf '%s\\n' 'CriomOS Desktop Codex gate: managed app-server control socket is unavailable' >&2
              exit 126
            fi
            exec ${codexCliPackage}/bin/codex app-server proxy --sock "$socket"
            ;;
          *)
            printf '%s\\n' 'CriomOS Desktop Codex gate: only inspection, app-server daemon version, and the managed app-server proxy are allowed' >&2
            exit 126
            ;;
        esac
        ;;
      3)
        if test "$1" = app-server && test "$2" = daemon && test "$3" = version; then
          exec ${codexCliPackage}/bin/codex "$@"
        fi
        printf '%s\\n' 'CriomOS Desktop Codex gate: only inspection, app-server daemon version, and the managed app-server proxy are allowed' >&2
        exit 126
        ;;
      *)
        printf '%s\\n' 'CriomOS Desktop Codex gate: only inspection, app-server daemon version, and the managed app-server proxy are allowed' >&2
        exit 126
        ;;
    esac
  '';
}
