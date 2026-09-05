{ pkgs, ... }:
let
  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf 'cwd=%s\n' "$PWD"
      printf '%s\n' "$@"
    '';
  };
  codexRemote = pkgs.callPackage ../../owned-agents/codex/remote.nix {
    codexCliPackage = codexFixture;
  };
in
pkgs.runCommand "codex-remote-contract" { } ''
  set -eu

  fixture_directory="$TMPDIR/codex-remote-cwd"
  mkdir "$fixture_directory"

  expected_output() {
    printf 'cwd=%s\n' "$1"
    shift
    printf '%s\n' "$@"
  }

  test "$(cd "$fixture_directory" && ${codexRemote}/bin/codex-remote resume thread-id)" = "$({
    expected_output "$fixture_directory" --remote unix:// resume thread-id
  })"
  test "$(cd "$fixture_directory" && ${codexRemote}/bin/codex-remote -- --remote unix:///other.sock)" = "$({
    expected_output "$fixture_directory" --remote unix:// -- --remote unix:///other.sock
  })"
  test "$(cd "$fixture_directory" && ${codexRemote}/bin/codex-remote --cd /worktree resume thread-id)" = "$({
    expected_output "$fixture_directory" --remote unix:// --cd /worktree resume thread-id
  })"
  touch "$out"
''
