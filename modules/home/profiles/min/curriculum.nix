{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.curriculum;
  deployment = pkgs.callPackage ../../../../packages/curriculum-resolver-deployment {
    inherit inputs;
  };
  homeDirectory = config.home.homeDirectory;
  rolesFile = "${homeDirectory}/.local/state/curriculum-040/roles.datom";
  recordsDirectory = "${homeDirectory}/primary/flows";
  curriculumEnvironment = deployment.environment homeDirectory rolesFile recordsDirectory;
in
{
  options.criomosHome.curriculum.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run the Curriculum Nexus paired with the stable Flow slot.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ deployment ];

    # Activation owns the authored registry at the exact state path consumed by
    # the stable Curriculum slot.
    home.file.".local/state/curriculum-040/roles.datom" = {
      source = "${inputs.curriculum-source}/roles.datom";
      force = true;
    };

    systemd.user.services.curriculum-nexus-040 = {
      Unit = {
        Description = "Curriculum Nexus paired with Flow 0.40";
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };
      Service = {
        RuntimeDirectory = "flow40-rt/curriculum";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "${homeDirectory}/primary";
        Environment = [
          "XDG_RUNTIME_DIR=%t/flow40-rt"
          "PATH=${
            lib.makeBinPath [
              pkgs.git
              pkgs.openssh
              pkgs.coreutils
            ]
          }"
        ]
        ++ curriculumEnvironment;
        ExecStart = "${deployment.runtime}/bin/curriculum-nexus";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
