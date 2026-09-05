{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex-remote";
  text = ''
    exec ${codexCliPackage}/bin/codex --remote unix:// "$@"
  '';
}
