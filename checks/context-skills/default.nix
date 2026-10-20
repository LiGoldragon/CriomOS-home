# Every module of the pinned cohort is a skill on every harness surface, and
# the skill text is the module's own text.
{ pkgs, inputs, ... }:
let
  skills = pkgs.callPackage ../../packages/context-skills { inherit inputs; };
  cohort = inputs.primary.inputs;
  # The Home module links each surface into the workspace when Curriculum
  # serves that workspace.
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../../modules/home/profiles/min/context-skills.nix
      {
        options.criomosHome.curriculum.enable = pkgs.lib.mkOption { type = pkgs.lib.types.bool; };
        config = {
          criomosHome.curriculum.enable = true;
          home = {
            username = "context-skills-check";
            homeDirectory = "/tmp/context-skills-check";
            stateVersion = "26.05";
          };
        };
      }
    ];
  };
  linked = map (surface: home.config.home.file."primary/${surface}".source) skills.surfaces;
in
assert linked == map (surface: "${skills}/${surface}") skills.surfaces;
pkgs.runCommand "context-skills-contract" { } ''
  set -eu
  expected=0
  for pair in \
    "${cohort.psyche-context}:vision intent spirit" \
    "${cohort.mind-context}:knowledge inquiry role" \
    "${cohort.field-context}:compensation role"; do
    root="''${pair%%:*}"
    for kind in ''${pair#*:}; do
      [ -d "$root/$kind" ] || continue
      for source in "$root/$kind"/*.md; do
        name="$kind-$(basename "$source" .md)"
        expected=$((expected + 1))
        for surface in ${pkgs.lib.concatStringsSep " " skills.surfaces}; do
          test -s "${skills}/$surface/$name/SKILL.md" || { echo "missing $surface/$name" >&2; exit 1; }
        done
        grep -q "^$name " "${skills}/modules"
      done
    done
  done
  test "$(wc -l < "${skills}/modules")" -eq "$expected"
  for surface in ${pkgs.lib.concatStringsSep " " skills.surfaces}; do
    test "$(ls "${skills}/$surface" | wc -l)" -eq "$expected"
  done
  cmp "${skills}/.claude/skills/vision-criomos/SKILL.md" "${cohort.psyche-context}/vision/criomos.md"
  grep -q '^name: vision-criomos$' "${skills}/.opencode/skills/vision-criomos/SKILL.md"
  grep -q '^disable-model-invocation: true$' "${skills}/.claude/skills/compensation-realization/SKILL.md"
  test -f "${skills}/.codex/skills/compensation-realization/agents/openai.yaml"
  if grep -q '{% if' "${skills}/.claude/skills/compensation-main-flow/SKILL.md"; then
    echo "harness directive left in a rendered skill" >&2; exit 1
  fi
  touch "$out"
''
