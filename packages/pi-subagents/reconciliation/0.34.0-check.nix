{
  pkgs,
  candidate,
  pi,
}:

pkgs.runCommand "pi-subagents-reconciliation-witness-0.34.0-check"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    packageRoot=${candidate}/share/pi-packages/pi-subagents
    test -f "$packageRoot/src/extension/index.ts"
    jq -e '.name == "pi-subagents" and .version == "0.34.0" and .pi.extensions == ["./src/extension/index.ts"]' \
      "$packageRoot/package.json"
    test -d "$packageRoot/node_modules/jiti"
    test -d "$packageRoot/node_modules/typebox"
    test -d "$packageRoot/node_modules/@earendil-works/pi-tui"
    test "$(wc -l < "$packageRoot/skills/pi-subagents/SKILL.md")" -le 150
    grep -F 'clarify === true' "$packageRoot/src/runs/foreground/chain-execution.ts"
    grep -F 'compactAsyncRunnerStderrAfterClose' "$packageRoot/src/runs/background/async-execution.ts"
    ! grep -F -- '--no-extensions' "$packageRoot/src/runs/shared/pi-args.ts"
    grep -F 'allowEmptyChangeEvidence' "$packageRoot/src/runs/shared/acceptance.ts"

    export HOME="$TMPDIR/home"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    export PI_PACKAGE_DIR=${pi}/lib/pi-monorepo/packages/coding-agent
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

    printf '{"type":"get_commands"}\n' | \
      ${pi}/bin/pi --mode rpc --no-session --no-context-files --no-skills \
        -e "$packageRoot/src/extension/index.ts" \
        > "$TMPDIR/pi-load.jsonl" 2> "$TMPDIR/pi-load.stderr"

    ! grep -F 'Failed to load extension' "$TMPDIR/pi-load.stderr"
    jq -e 'select(.type == "response" and .command == "get_commands" and .success == true)' \
      "$TMPDIR/pi-load.jsonl" >/dev/null

    touch "$out"
  ''
