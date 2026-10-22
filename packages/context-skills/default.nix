# The command that regenerates the Primary workspace skill directories from
# the main of psyche-context, mind-context and field-context as it stands.
# It reads no flake input: a landing on main is the only thing that moves it.
{ pkgs, ... }:
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
