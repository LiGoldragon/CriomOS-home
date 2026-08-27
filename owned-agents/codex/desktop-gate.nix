{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex";
  text = ''
    # Desktop may inspect its bundled candidate and probe the already-owned
    # local daemon.  Every invocation that could create another writer is
    # deliberately outside this executable's authority.
    case "$*" in
      --version|-V|version|--help|-h|help|"app-server daemon version")
        exec ${codexCliPackage}/bin/codex "$@"
        ;;
      *)
        printf '%s\\n' 'CriomOS Desktop Codex gate: only inspection and app-server daemon version are allowed' >&2
        exit 126
        ;;
    esac
  '';
}
