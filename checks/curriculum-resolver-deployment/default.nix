{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/curriculum-resolver-deployment { inherit inputs; };
in pkgs.runCommand "curriculum-resolver-contract" {
  nativeBuildInputs = [ pkgs.git ];
} ''
  set -eu
  activation=${deployment.activate}/bin/activate-declared-curriculum
  grep -F 'curriculum-nexus.service' "$activation"
  ! grep -Eiq 'flow-nexus|flow\.sock|flow-meta\.sock|flow\.sema' "$activation"
  grep -F '${deployment.projectRoles}/bin/project-declared-curriculum-roles' ${deployment.unit}
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  ${pkgs.lib.concatMapStringsSep "\n" (value: "export " + pkgs.lib.escapeShellArg value) (deployment.environment "$TMPDIR/workspace")}
  make_source() {
    name="$1"
    source="$2"
    target="$TMPDIR/origins/$name"
    mkdir -p "$target"
    cp -R "$source"/. "$target"/
    git -C "$target" init --quiet --initial-branch=main
    git -C "$target" config user.email test@example.invalid
    git -C "$target" config user.name CurriculumTest
    git -C "$target" add --all
    git -C "$target" commit --quiet -m "initial context"
  }
  make_source psyche ${deployment.psyche-context}
  make_source mind ${deployment.mind-context}
  make_source field ${deployment.field-context}
  export CURRICULUM_PSYCHES_REPOSITORY_URL="$TMPDIR/origins/psyche"
  export CURRICULUM_MIND_CONTEXT_URL="$TMPDIR/origins/mind"
  export CURRICULUM_FIELD_CONTEXT_URL="$TMPDIR/origins/field"
  ${deployment.refresh}/bin/curriculum-refresh-contexts
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR/curriculum"
  ${deployment.runtime}/bin/curriculum-nexus > "$TMPDIR/nexus.log" 2>&1 &
  resolver_pid=$!
  stop_resolver() {
    kill "$resolver_pid" 2>/dev/null || true
    wait "$resolver_pid" || true
  }
  trap stop_resolver EXIT
  attempts=200
  while [ ! -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ]; do
    if ! kill -0 "$resolver_pid" 2>/dev/null; then cat "$TMPDIR/nexus.log"; exit 1; fi
    attempts=$((attempts - 1)); test "$attempts" -gt 0
    sleep 0.05
  done
  query='ComposeStartup.{ { Psyche core Secondary } Claude [ spirit-core intent-main-flow ] [ compensation-behavior ] }'
  ${deployment.agents}/bin/install-curriculum-claude-agents
  for role in general-purpose book-author; do
    for module in vision-book compensation-book-crystallization; do
      test "$(grep -Fc "<!-- module: $module -->" "$HOME/.claude/agents/$role.md")" -eq 1
    done
  done
  ${deployment.runtime}/bin/curriculum "$query" > "$TMPDIR/composed.datom"
  grep -q '^StartupComposed\.' "$TMPDIR/composed.datom"
  grep -q 'These are your skills, given here; do not reload them.' "$TMPDIR/composed.datom"
  ${deployment.runtime}/bin/curriculum 'ComposeRole.{ illustrator ClaudeAgent }' > "$TMPDIR/role.datom"
  grep -q '^RoleComposed\.' "$TMPDIR/role.datom"
  chmod u+w "$TMPDIR/origins/psyche/vision/book.md"
  printf '\nLIVE_ROLE_SOURCE_WITNESS\n' >> "$TMPDIR/origins/psyche/vision/book.md"
  git -C "$TMPDIR/origins/psyche" add vision/book.md
  git -C "$TMPDIR/origins/psyche" commit --quiet -m "refresh role context"
  latest_role=$(git -C "$TMPDIR/origins/psyche" rev-parse HEAD)
  ${deployment.refresh}/bin/curriculum-refresh-contexts
  ${deployment.runtime}/bin/curriculum \
    'ComposeRole.{ illustrator ClaudeAgent }' > "$TMPDIR/latest-role.datom"
  grep -q 'LIVE_ROLE_SOURCE_WITNESS' "$TMPDIR/latest-role.datom"
  grep -q "$latest_role" "$TMPDIR/latest-role.datom"
  ${deployment.projector}/bin/curriculum-deploy \
    "ProjectRoles.{ «$XDG_RUNTIME_DIR/curriculum/curriculum.sock» «$TMPDIR/workspace» [ { { general-purpose ClaudeAgent } «.claude/agents/general-purpose.md» } { { book-author ClaudeAgent } «.claude/agents/book-author.md» } ] }" \
    > "$TMPDIR/projected.datom"
  grep -Fx 'RolesProjected.{ 2 }' "$TMPDIR/projected.datom"
  test -s "$TMPDIR/workspace/.claude/agents/general-purpose.md"
  test -s "$TMPDIR/workspace/.claude/agents/book-author.md"
  test -s "$TMPDIR/workspace/skills/generated-role-outputs.datom"
  test -s "$TMPDIR/workspace/skills/generated-role-provenance.datom"
  test "$(find "$TMPDIR/workspace/.claude/agents" -type f | wc -l)" -eq 2
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ spirit-core intent-main-flow ] [ /tmp/inline-context ] }' > "$TMPDIR/path.out" 2>&1; then
    echo "Curriculum admitted a path-shaped module ID" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ intent-main-flow ] [ spirit-core ] }' > "$TMPDIR/placement.out" 2>&1; then
    echo "Curriculum admitted USER spirit" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum RebuildSkills > "$TMPDIR/retired.out" 2>&1; then
    echo "Curriculum retained the retired file-projection API" >&2
    exit 1
  fi
  stop_resolver
  trap - EXIT
  test -f "$TMPDIR/origins/psyche/intent/psyche.md"
  chmod u+w "$TMPDIR/origins/psyche/intent/psyche.md"
  chmod u+w "$TMPDIR/origins/psyche/intent/main-flow.md"
  printf '\nEvery line of context is marked short-term or long-term.\n' >> "$TMPDIR/origins/psyche/intent/psyche.md"
  printf '\nSTART_LATEST_FLOW_CONTEXT_WITNESS\n' >> "$TMPDIR/origins/psyche/intent/main-flow.md"
  git -C "$TMPDIR/origins/psyche" add intent/main-flow.md
  git -C "$TMPDIR/origins/psyche" add intent/psyche.md
  git -C "$TMPDIR/origins/psyche" commit --quiet -m "new main context"
  latest=$(git -C "$TMPDIR/origins/psyche" rev-parse HEAD)
  ${deployment.refresh}/bin/curriculum-refresh-contexts
  XDG_RUNTIME_DIR="$TMPDIR/runtime-next"
  export XDG_RUNTIME_DIR
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR/curriculum"
  ${deployment.runtime}/bin/curriculum-nexus > "$TMPDIR/nexus-next.log" 2>&1 &
  resolver_pid=$!
  trap stop_resolver EXIT
  attempts=200
  while [ ! -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ]; do
    if ! kill -0 "$resolver_pid" 2>/dev/null; then cat "$TMPDIR/nexus-next.log"; exit 1; fi
    attempts=$((attempts - 1)); test "$attempts" -gt 0
    sleep 0.05
  done
  ${deployment.runtime}/bin/curriculum \
    'ComposeStartup.{ { Psyche core Secondary } Claude [ intent-psyche intent-main-flow ] [] }' > "$TMPDIR/latest.datom"
  grep -q 'Every line of context is marked short-term or long-term.' "$TMPDIR/latest.datom"
  grep -q 'START_LATEST_FLOW_CONTEXT_WITNESS' "$TMPDIR/latest.datom"
  ${deployment.runtime}/bin/curriculum 'ResolveSources.[ intent-psyche intent-main-flow ]' > "$TMPDIR/latest-sources.datom"
  grep -q "$latest" "$TMPDIR/latest-sources.datom"
  touch "$out"
''
