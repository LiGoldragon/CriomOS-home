{ pkgs, ... }:
let
  codexFixture = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf 'cwd=%s\n' "$PWD"
      printf '%s\n' "$@"
    '';
  };
  systemctlFixture = pkgs.writeShellApplication {
    name = "systemctl";
    text = ''
      if [ "''${1:-}" = --user ] && [ "''${2:-}" = is-active ]; then
        exit 0
      fi
      printf 'systemctl'
      printf ' %s' "$@"
      printf '\n'
    '';
  };
  ghosttyFixture = pkgs.writeShellApplication {
    name = "ghostty";
    text = ''
      printf 'ghostty'
      printf ' %s' "$@"
      printf '\n'
    '';
  };
  systemdRunFixture = pkgs.writeShellApplication {
    name = "systemd-run";
    text = ''
      printf 'systemd-run'
      printf ' %s' "$@"
      printf '\n'
    '';
  };
  codexRemote = pkgs.callPackage ../../owned-agents/codex/remote.nix {
    codexCliPackage = codexFixture;
    systemctl = systemctlFixture;
    ghostty = ghosttyFixture;
    systemdRun = systemdRunFixture;
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

  printf 'Synthetic desktop prompt\n' > "$TMPDIR/prompt"
  test "$(${codexRemote}/bin/codex-desktop fresh "$TMPDIR/prompt" "$fixture_directory")" = "$({
    printf '%s\n' 'systemd-run --user --scope --collect --quiet --property=CPUWeight=1000 --property=IOWeight=1000 --property=MemoryAccounting=yes --property=MemoryLow=512M --property=OOMPolicy=continue '"${ghosttyFixture}"'/bin/ghostty --gtk-single-instance=false --class=criomos-codex-desktop --title=Codex fresh --working-directory='"$fixture_directory"' --wait-after-command -e '"${codexRemote.codexRemote}"'/bin/codex-remote --cd '"$fixture_directory"' --model gpt-6-astra Synthetic desktop prompt'
  })"
  test "$(${codexRemote}/bin/codex-desktop resume 01999999-aaaa-bbbb-cccc-123456789abc "$fixture_directory")" = "$({
    printf '%s\n' 'systemd-run --user --scope --collect --quiet --property=CPUWeight=1000 --property=IOWeight=1000 --property=MemoryAccounting=yes --property=MemoryLow=512M --property=OOMPolicy=continue '"${ghosttyFixture}"'/bin/ghostty --gtk-single-instance=false --class=criomos-codex-desktop --title=Codex resume 01999999-aaaa-bbbb-cccc-123456789abc --working-directory='"$fixture_directory"' --wait-after-command -e '"${codexRemote.codexRemote}"'/bin/codex-remote --cd '"$fixture_directory"' resume 01999999-aaaa-bbbb-cccc-123456789abc'
  })"
  test "$(${codexRemote}/bin/codex-desktop status)" = 'systemctl --user status --no-pager codex-remote-control.service'
  test "$(${codexRemote}/bin/codex-desktop restart-service)" = "$({
    printf '%s\n' 'systemctl --user restart codex-remote-control.service'
    printf '%s\n' 'systemctl --user status --no-pager codex-remote-control.service'
  })"

  if ${codexRemote}/bin/codex-desktop resume latest "$fixture_directory" > "$TMPDIR/latest-out" 2> "$TMPDIR/latest-err"; then
    echo 'codex-desktop accepted a non-exact resume identifier' >&2
    exit 1
  fi
  grep -F 'exact Codex thread UUID' "$TMPDIR/latest-err"
  touch "$out"
''
