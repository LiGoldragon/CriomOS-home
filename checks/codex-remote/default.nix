{ pkgs, ... }:
let
  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf '%s\\n' "$@"
    '';
  };
  codexRemote = pkgs.callPackage ../../owned-agents/codex/remote.nix {
    codexCliPackage = codexFixture;
  };
in
pkgs.runCommand "codex-remote-contract" { } ''
  set -eu

  test "$( ${codexRemote}/bin/codex-remote resume thread-id )" = "$({
    printf '%s\\n' --remote unix:// resume thread-id
  })"
  test "$( ${codexRemote}/bin/codex-remote -- --remote unix:///other.sock )" = "$({
    printf '%s\\n' --remote unix:// -- --remote unix:///other.sock
  })"
  touch "$out"
''
