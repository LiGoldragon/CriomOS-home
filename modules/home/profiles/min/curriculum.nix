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
  deployment = pkgs.callPackage ../../../../packages/curriculum-resolver-deployment { inherit inputs; };
  curriculumPackage = deployment.runtime;
  homeDirectory = config.home.homeDirectory;
  curriculumEnvironment = deployment.environment homeDirectory;

in
{
  options.criomosHome.curriculum.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Run Curriculum only for a target with declared roots and workspace.";
  };

  config = {
    home.packages = [ deployment ];

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
      # Resolver startup reads its immutable registry; projection is explicit.
      Restart = "on-failure";
      RestartSec = "2s";
    };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
