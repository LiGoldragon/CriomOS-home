{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/curriculum-resolver-deployment { inherit inputs; };
  fixtureRefresh = pkgs.writeShellScript "curriculum-context-fixture-refresh" "exit 0";
in
pkgs.runCommand "curriculum-resolver-contract" { } ''
  set -eu
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  ${pkgs.lib.concatMapStringsSep "\n" (value: "export " + pkgs.lib.escapeShellArg value) (
    deployment.environment "$TMPDIR/workspace" "${inputs.curriculum-source}/roles.datom"
      "$TMPDIR/records"
  )}
  export CURRICULUM_PSYCHES_REPOSITORY_DIR="$TMPDIR/workspace/.local/state/curriculum-context/psyche-context"
  export CURRICULUM_MIND_CONTEXT_DIR="$TMPDIR/workspace/.local/state/curriculum-context/mind-context"
  export CURRICULUM_FIELD_CONTEXT_DIR="$TMPDIR/workspace/.local/state/curriculum-context/field-context"
  export CURRICULUM_RECORDS_DIR="$TMPDIR/records"
  export CURRICULUM_CONTEXT_REFRESH_PROGRAM=${fixtureRefresh}
  mkdir -p "$CURRICULUM_PSYCHES_REPOSITORY_DIR" "$CURRICULUM_MIND_CONTEXT_DIR" "$CURRICULUM_FIELD_CONTEXT_DIR"
  cp -R ${inputs.primary.inputs.psyche-context}/. "$CURRICULUM_PSYCHES_REPOSITORY_DIR/"
  cp -R ${inputs.primary.inputs.mind-context}/. "$CURRICULUM_MIND_CONTEXT_DIR/"
  cp -R ${inputs.primary.inputs.field-context}/. "$CURRICULUM_FIELD_CONTEXT_DIR/"
  for directory in "$CURRICULUM_PSYCHES_REPOSITORY_DIR" "$CURRICULUM_MIND_CONTEXT_DIR" "$CURRICULUM_FIELD_CONTEXT_DIR"; do
    ${pkgs.git}/bin/git -C "$directory" init --quiet
    ${pkgs.git}/bin/git -C "$directory" -c user.name=Fixture -c user.email=fixture.invalid add .
    ${pkgs.git}/bin/git -C "$directory" -c user.name=Fixture -c user.email=fixture.invalid commit --quiet -m fixture
  done
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR/curriculum" "$TMPDIR/records"
  ${deployment.runtime}/bin/curriculum-nexus > "$TMPDIR/nexus.log" 2>&1 &
  resolver_pid=$!
  trap 'kill "$resolver_pid" 2>/dev/null || true; wait "$resolver_pid" || true' EXIT
  attempts=200
  while [ ! -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ]; do
    if ! kill -0 "$resolver_pid" 2>/dev/null; then cat "$TMPDIR/nexus.log"; exit 1; fi
    attempts=$((attempts - 1)); test "$attempts" -gt 0
    sleep 0.05
  done
  query='ComposeStartup.{ { Psyche core Secondary } Claude [ spirit:core intent:main-flow ] [ knowledge:vocabulary ] [] }'
  ${deployment.runtime}/bin/curriculum "$query" > "$TMPDIR/composed.datom"
  grep -q '^StartupComposed\.' "$TMPDIR/composed.datom"
  grep -q 'These are your skills, given here; do not reload them.' "$TMPDIR/composed.datom"
  ${deployment.runtime}/bin/curriculum 'ComposeRole.{ illustrator ClaudeAgent }' > "$TMPDIR/role.datom"
  grep -q '^RoleComposed\.' "$TMPDIR/role.datom"
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ spirit:core intent:main-flow ] [ /tmp/inline-context ] [] }' > "$TMPDIR/path.out" 2>&1; then
    echo "Curriculum admitted a path-shaped module ID" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ intent:main-flow ] [ spirit:core ] [] }' > "$TMPDIR/placement.out" 2>&1; then
    echo "Curriculum admitted USER spirit" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum RebuildSkills > "$TMPDIR/retired.out" 2>&1; then
    echo "Curriculum retained the retired file-projection API" >&2
    exit 1
  fi
  touch "$out"
''
