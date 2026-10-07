{
  config,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  curriculumPackage = inputs.primary.packages.${system}.curriculum;
  homeDirectory = config.home.homeDirectory;
in
{
  home.packages = [ curriculumPackage ];

  systemd.user.services.curriculum-nexus = {
    Unit = {
      Description = "Curriculum skill registry and projection Nexus";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };

    Service = {
      RuntimeDirectory = "curriculum";
      RuntimeDirectoryMode = "0700";
      WorkingDirectory = "${homeDirectory}/primary";
      Environment = [
        "XDG_RUNTIME_DIR=%t"
        "CURRICULUM_PSYCHES_SKILLS_DIR=/git/github.com/LiGoldragon/psyche-skills/skills"
        "CURRICULUM_MIND_SKILLS_DIR=/git/github.com/LiGoldragon/mind-skills/skills"
        "CURRICULUM_FIELD_SKILLS_DIR=/git/github.com/LiGoldragon/field-skills/skills"
        "CURRICULUM_ROLES_FILE=${inputs."curriculum-source"}/roles.datom"
        "CURRICULUM_WORKSPACE=${homeDirectory}/primary"
      ];
      ExecStart = "${curriculumPackage}/bin/curriculum-nexus";
      ExecStartPost = "${curriculumPackage}/bin/curriculum RebuildSkills";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
