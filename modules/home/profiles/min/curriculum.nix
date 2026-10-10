{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.curriculum;
  system = pkgs.stdenv.hostPlatform.system;
  curriculumPackage = inputs.primary.packages.${system}.curriculum;
  homeDirectory = config.home.homeDirectory;
  curriculumEnvironment = [
    "CURRICULUM_PSYCHES_REPOSITORY_DIR=${inputs.psyche-skills}"
    "CURRICULUM_MIND_SKILLS_DIR=/git/github.com/LiGoldragon/mind-skills/skills"
    "CURRICULUM_FIELD_SKILLS_DIR=/git/github.com/LiGoldragon/field-skills/skills"
    "CURRICULUM_ROLES_FILE=${inputs."curriculum-source"}/roles.datom"
    "CURRICULUM_WORKSPACE=${homeDirectory}/primary"
  ];
  curriculumCli = pkgs.writeShellScriptBin "curriculum" ''
    export CURRICULUM_PSYCHES_REPOSITORY_DIR=${inputs.psyche-skills}
    export CURRICULUM_MIND_SKILLS_DIR=/git/github.com/LiGoldragon/mind-skills/skills
    export CURRICULUM_FIELD_SKILLS_DIR=/git/github.com/LiGoldragon/field-skills/skills
    export CURRICULUM_ROLES_FILE=${inputs."curriculum-source"}/roles.datom
    export CURRICULUM_WORKSPACE=${homeDirectory}/primary
    exec ${curriculumPackage}/bin/curriculum "$@"
  '';
  rebuildAfterSocketReady = pkgs.writeShellScript "curriculum-rebuild-after-socket-ready" ''
    set -eu
    socket="$XDG_RUNTIME_DIR/curriculum/curriculum.sock"
    attempts=250
    while [ "$attempts" -gt 0 ]; do
      if [ -S "$socket" ]; then
        exec ${curriculumPackage}/bin/curriculum RebuildSkills
      fi
      attempts=$((attempts - 1))
      ${pkgs.coreutils}/bin/sleep 0.02
    done
    echo "Curriculum Nexus socket did not become ready" >&2
    exit 1
  '';
in
{
  options.criomosHome.curriculum.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Run Curriculum only for a target with declared roots and workspace.";
  };

  config = {
    home.packages = [ curriculumCli ];

    systemd.user.services.curriculum-nexus = lib.mkIf cfg.enable {
    Unit = {
      Description = "Curriculum skill registry and projection Nexus";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };

    Service = {
      RuntimeDirectory = "curriculum";
      RuntimeDirectoryMode = "0700";
      WorkingDirectory = "${homeDirectory}/primary";
      Environment = [ "XDG_RUNTIME_DIR=%t" ] ++ curriculumEnvironment;
      ExecStart = "${curriculumPackage}/bin/curriculum-nexus";
      ExecStartPost = "${rebuildAfterSocketReady}";
      Restart = "on-failure";
      RestartSec = "2s";
    };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
