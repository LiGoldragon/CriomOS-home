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
  deployment = pkgs.callPackage ../../../../packages/curriculum-resolver-deployment {
    inherit inputs;
  };
  curriculumPackage = deployment.runtime;
  homeDirectory = config.home.homeDirectory;
  curriculumEnvironment = deployment.environment homeDirectory;
  knownPrimaryPin = pkgs.writeShellScript "retire-known-curriculum-primary-pin" ''
    set -eu
    pin="$HOME/.config/systemd/user/curriculum-nexus.service.d/60-primary-pin.conf"
    if [ -e "$pin" ]; then
      if [ -L "$pin" ] || [ "$(sha256sum "$pin" | cut -d' ' -f1)" != \
        6fc4892c80db9172ba2892f6a8601853c09a85bed5d62ae128f2c63809c357ba ]; then
        echo "refusing to replace unknown curriculum 60-primary-pin.conf" >&2
        exit 1
      fi
      rm -f "$pin"
    fi
  '';

in
{
  options.criomosHome.curriculum.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run Curriculum only for a target with declared roots and workspace.";
  };

  config = {
    home.packages = [ deployment ];
    xdg.configFile."systemd/user/curriculum-nexus.service.d/50-declared-runtime.conf" =
      lib.mkIf cfg.enable
        {
          source = deployment.unit;
          force = true;
        };
    home.activation.retireKnownCurriculumPrimaryPin = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      ${knownPrimaryPin}
    '';
    xdg.configFile."systemd/user/curriculum-nexus.service.d/60-primary-pin.conf" = lib.mkIf cfg.enable {
      text = ''
        [Service]
        Environment=CURRICULUM_RECORDS_DIR=${homeDirectory}/primary/flows
        Environment=CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom
        ExecStart=
        ExecStart=${deployment.runtime}/bin/curriculum-nexus
        ExecStartPost=
        ExecStartPost=${deployment.agents}/bin/install-curriculum-claude-agents
      '';
      force = true;
    };

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
        Environment = [ "XDG_RUNTIME_DIR=%t" "PATH=${pkgs.lib.makeBinPath [ pkgs.git ]}" ] ++ curriculumEnvironment;
        ExecStart = "${curriculumPackage}/bin/curriculum-nexus";
        # Resolver startup reads its immutable registry; projection is explicit.
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
