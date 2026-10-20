# Every context module of the one pinned cohort, installed as a skill in the
# directory each harness reads. The cohort is primary.inputs.{psyche,mind,
# field}-context in this flake: the same revisions Curriculum composes flow
# starts from. A landing regenerates it by moving that pin:
#   nix build .#context-skills --override-input primary/psyche-context \
#     github:LiGoldragon/psyche-context/<revision>
{ pkgs, inputs, ... }:
let
  cohort = inputs.primary.inputs;
  sources = [
    cohort.psyche-context
    cohort.mind-context
    cohort.field-context
  ];
in
pkgs.runCommand "context-skills"
  {
    nativeBuildInputs = [ pkgs.babashka ];
    passthru = {
      surfaces = [
        ".claude/skills"
        ".agents/skills"
        ".codex/skills"
        ".pi/skills"
        ".opencode/skills"
      ];
      revisions = map (source: source.rev) sources;
    };
  }
  ''
    mkdir -p "$out"
    bb ${./generate.clj} "$out" ${
      pkgs.lib.concatMapStringsSep " " (source: "${source}=${source.rev}") sources
    }
  ''
