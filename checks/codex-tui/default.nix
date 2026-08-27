{ pkgs, ... }:
let
  codexTuiFixtureCli = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf '%s\\n' "$@"
    '';
  };
  codexTuiFixture = pkgs.callPackage ../../owned-agents/codex/tui.nix {
    codexCliPackage = codexTuiFixtureCli;
  };
in
pkgs.runCommand "codex-tui-launch-contract" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu

  assert_output() {
    label="$1"
    actual="$2"
    expected="$3"
    if [ "$actual" != "$expected" ]; then
      printf '%s actual:\n%s\nexpected:\n%s\n' "$label" "$actual" "$expected" >&2
      exit 1
    fi
  }

  first_directory="$TMPDIR/first-directory"
  second_directory="$TMPDIR/second-directory"
  explicit_directory="$TMPDIR/explicit-directory"
  mkdir -p "$first_directory" "$second_directory" "$explicit_directory"

  first_actual="$(cd "$first_directory" && ${codexTuiFixture}/bin/codex --remote unix:// first)"
  first_expected="$(printf '%s\\n' --cd "$first_directory" --sandbox danger-full-access --ask-for-approval never --remote unix:// first)"
  assert_output first-directory "$first_actual" "$first_expected"

  second_actual="$(cd "$second_directory" && ${codexTuiFixture}/bin/codex second)"
  second_expected="$(printf '%s\\n' --cd "$second_directory" --sandbox danger-full-access --ask-for-approval never --remote unix:// second)"
  assert_output second-directory "$second_actual" "$second_expected"

  explicit_actual="$(cd "$first_directory" && ${codexTuiFixture}/bin/codex --remote unix:// --cd "$explicit_directory" --sandbox workspace-write --ask-for-approval on-request explicit)"
  explicit_expected="$(printf '%s\\n' --remote unix:// --cd "$explicit_directory" --sandbox workspace-write --ask-for-approval on-request explicit)"
  assert_output explicit-overrides "$explicit_actual" "$explicit_expected"

  sandbox_actual="$(cd "$first_directory" && ${codexTuiFixture}/bin/codex --sandbox read-only sandbox-override)"
  sandbox_expected="$(printf '%s\\n' --cd "$first_directory" --ask-for-approval never --remote unix:// --sandbox read-only sandbox-override)"
  assert_output sandbox-override "$sandbox_actual" "$sandbox_expected"

  approval_actual="$(cd "$first_directory" && ${codexTuiFixture}/bin/codex -a on-request approval-override)"
  approval_expected="$(printf '%s\\n' --cd "$first_directory" --sandbox danger-full-access --remote unix:// -a on-request approval-override)"
  assert_output approval-override "$approval_actual" "$approval_expected"

  raw_actual="$(cd "$first_directory" && ${codexTuiFixture}/bin/codex exec one-shot)"
  assert_output raw-subcommand "$raw_actual" "$(printf '%s\\n' exec one-shot)"

  if ${codexTuiFixture}/bin/codex --remote unix:///tmp/other.sock resume thread-id >/dev/null 2>&1; then
    echo 'accepted an unmanaged Codex app-server route' >&2
    exit 1
  fi

  touch "$out"
''
