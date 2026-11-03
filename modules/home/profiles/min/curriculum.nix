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
  declaredPrimaryPin = pkgs.writeText "curriculum-primary-pin.conf" ''
    [Service]
    Environment=CURRICULUM_RECORDS_DIR=${homeDirectory}/primary/flows
    Environment=CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom
    ExecStart=
    ExecStart=${deployment.runtime}/bin/curriculum-nexus
    ExecStartPost=
    ExecStartPost=${deployment.agents}/bin/install-curriculum-claude-agents
  '';
  knownPrimaryPin = pkgs.writeShellScript "retire-known-curriculum-primary-pin" ''
    set -eu
    pin="$HOME/.config/systemd/user/curriculum-nexus.service.d/60-primary-pin.conf"
    if [ -e "$pin" ]; then
      pin_hash=$(sha256sum "$pin" | cut -d' ' -f1)
      if [ -L "$pin" ]; then
        target=$(readlink -f "$pin")
        case "$target" in /nix/store/*) ;; *) echo "refusing unknown curriculum 60-primary-pin symlink" >&2; exit 1 ;; esac
        cmp -s "$target" "${declaredPrimaryPin}" || { echo "refusing unknown curriculum 60-primary-pin symlink" >&2; exit 1; }
        exit 0
      fi
      case "$pin_hash" in
        6fc4892c80db9172ba2892f6a8601853c09a85bed5d62ae128f2c63809c357ba) ;;
        *)
        echo "refusing to replace unknown curriculum 60-primary-pin.conf" >&2
        exit 1
        ;;
      esac
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
      source = declaredPrimaryPin;
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
