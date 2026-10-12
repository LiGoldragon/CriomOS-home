{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/curriculum-resolver-deployment { inherit inputs; };
in pkgs.runCommand "curriculum-resolver-contract" { } ''
  set -eu
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  export CURRICULUM_PSYCHES_REPOSITORY_DIR=${deployment.psyche-skills}
  export CURRICULUM_MIND_SKILLS_DIR=${deployment.mind-skills}/skills
  export CURRICULUM_FIELD_SKILLS_DIR=${deployment.field-skills}/skills
  export CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom
  export CURRICULUM_WORKSPACE="$TMPDIR/workspace"
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR/curriculum" "$CURRICULUM_WORKSPACE"
  ${deployment.runtime}/bin/curriculum-nexus > "$TMPDIR/nexus.log" 2>&1 &
  resolver_pid=$!
  trap 'kill "$resolver_pid" 2>/dev/null || true; wait "$resolver_pid" || true' EXIT
  attempts=200
  while [ ! -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ]; do
    if ! kill -0 "$resolver_pid" 2>/dev/null; then cat "$TMPDIR/nexus.log"; exit 1; fi
    attempts=$((attempts - 1)); test "$attempts" -gt 0
    sleep 0.05
  done
  ${deployment.runtime}/bin/curriculum 'ResolveSkills.[ spirit-core vision-design intent-psyche operation-main-flow compensation-book-distillation compensation-truth compensation-orders compensation-prose compensation-understanding compensation-launch compensation-design compensation-default-effort compensation-messenger-clj compensation-temporary knowledge-psyche operation-psyche-interraction knowledge-vocabulary operation-edit-coordination ]' > "$TMPDIR/skills.datom"
  for skill in spirit-core vision-design intent-psyche operation-main-flow; do
    grep -q "$skill" "$TMPDIR/skills.datom"
  done
  touch "$out"
''
