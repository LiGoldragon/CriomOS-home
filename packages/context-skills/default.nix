# The command that regenerates the Primary workspace skill directories from
# the main of psyche-belief, mind-belief and field-belief as it stands.
# The resolver and exporter share one typed placement reader.
{ pkgs, inputs, ... }:
let
  curriculum = pkgs.callPackage ../curriculum-resolver-deployment { inherit inputs; };
in
pkgs.writeShellApplication {
  name = "context-skills-regenerate";
  runtimeInputs = [
    pkgs.babashka
    pkgs.coreutils
    pkgs.git
    pkgs.gnutar
    pkgs.openssh
    pkgs.rsync
    pkgs.util-linux
  ];
  excludeShellChecks = [ "SC2086" ];
  text = ''
    export GENERATOR=${./generate.clj}
    export CURRICULUM_SKILL_INVENTORY=${curriculum.runtime}/bin/curriculum-skill-inventory
    ${builtins.readFile ./regenerate.sh}
  '';
  passthru.surfaces = [
    ".claude/skills"
    ".agents/skills"
    ".codex/skills"
    ".pi/skills"
    ".opencode/skills"
  ];
}
