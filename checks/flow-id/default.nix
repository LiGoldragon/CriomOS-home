{ inputs, pkgs, ... }:
let
  flowId = inputs.harness.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
pkgs.runCommand "flow-id-home-package" { } ''
  test -x ${flowId}/bin/flow-id
  flowsRoot="$TMPDIR/flows"
  mkdir -m 700 "$flowsRoot"
  claudeSession=a1b2c3d4-e5f6-4a78-9abc-def012345678
  test "$("${flowId}/bin/flow-id" claude --flows-root "$flowsRoot" --parent-session "$claudeSession")" = a1b2c3
  test "$("${flowId}/bin/flow-id" claude --flows-root "$flowsRoot" --parent-session "$claudeSession")" = a1b2c3
  test "$(stat -c %a "$flowsRoot/a1b2c3")" = 700
  test "$(stat -c %a "$flowsRoot/.a1b2c3.flow-id")" = 600
  test "$(stat -c %a "$flowsRoot/.a1b2c3.flow-id.lock")" = 600
  ! "${flowId}/bin/flow-id" claude --flows-root "$flowsRoot" --parent-session a1b2c3d4-e5f6-5a78-9abc-def012345678
  test "$(CODEX_SESSION_ID=01a05e95-1234-5678-9abc-000715d46abc "${flowId}/bin/flow-id" codex --flows-root "$flowsRoot")" = 715d46
  touch "$out"
''
