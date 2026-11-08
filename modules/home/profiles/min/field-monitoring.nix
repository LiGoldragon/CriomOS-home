{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Field monitoring — callable versions of four jobs that once ran from
# hand-made timers on ouranos. Their scripts come from pinned sources instead
# of working copies. Every job is off unless enabled and has no schedule.
#
let
  inherit (lib)
    concatStringsSep
    filter
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
  cfg = config.criomosHome.fieldMonitoring;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = config.home.homeDirectory;

  herdrPackage = config.criomosHome.herdr.package;
  messengerCljPackage = inputs.messenger-clj.packages.${system}.default;
  codexPackage = config.criomos.corePackages.codex;
  claudePackage = config.criomos.corePackages.claude;

  # Pinned script sources. core-checkup matches the store source the live
  # unit ran (primary d3002f4b); the Field census and checkup come from primary
  # main 1e8eee26; Field Luna research comes from field main.
  coreCheckupSource = inputs.core-checkup-source;
  fieldMonitoringSource = inputs.field-monitoring-source;
  fieldSource = inputs.field-luna-research-source;

  nodeBin = "${pkgs.nodejs}/bin/node";

  coreCheckupRoster = pkgs.writeText "core-checkup-roster.json" (builtins.toJSON cfg.coreCheckup.roster);

  fieldLunaResearchRunner = pkgs.writeShellApplication {
    name = "field-luna-research-run";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.coreutils
      pkgs.nodejs
      herdrPackage
      codexPackage
    ];
    # Behaviour of field/bin/field-luna-research-run: one flock-guarded
    # attempt per state directory, then the pinned research script.
    text = ''
      state_dir=''${XDG_STATE_HOME:-"$HOME/.local/state"}/field-luna-research
      arguments=("$@")
      for ((index=0; index < ''${#arguments[@]}; index++)); do
        if [[ ''${arguments[index]} == --state-dir ]] && (( index + 1 < ''${#arguments[@]} )); then state_dir=''${arguments[index + 1]}; fi
      done
      mkdir -p -- "$state_dir"
      exec 9>"$state_dir/cycle.lock"
      if ! flock -n 9; then
        printf '%s\n' 'another Field Luna research attempt is active' >&2
        exit 1
      fi
      exec ${nodeBin} ${fieldSource}/bin/field-luna-research.mjs "$@"
    '';
  };

  monitorNames = {
    coreCheckup = "core-checkup";
    fieldCensus = "field-census";
    fieldCheckupShadow = "field-checkup-shadow";
    fieldLunaResearch = "field-luna-research";
  };
  enabledUnitNames = lib.concatMap (option: [
    "${monitorNames.${option}}.service"
    "${monitorNames.${option}}.timer"
  ]) (filter (option: cfg.${option}.enable) (builtins.attrNames monitorNames));
in
{
  options.criomosHome.fieldMonitoring = {
    primaryRoot = mkOption {
      type = types.str;
      default = "${homeDirectory}/primary";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/primary"'';
      description = "Primary workspace the monitors observe (data root, never a script source).";
    };
    sourceRevisions = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      default = {
        core-checkup-source = "d3002f4bf9ae81852c3b7e5e65f4793afbc1e3da";
        field-monitoring-source = "1e8eee26974c68857a3caf9d95ceff4570146294";
        field-luna-research-source = "34fe6c8899684de4f892142d4357a3ca3d67895b";
      };
      description = "Pinned script source revisions carried by the flake inputs of the same names.";
    };

    coreCheckup = {
      enable = mkEnableOption "the bounded monitoring-only core checkup callable service";
      roster = mkOption {
        type = types.nullOr (types.attrsOf types.anything);
        default = null;
        description = "Endpoint and unit roster (JSON). Host data: supplied by whoever enables the checkup.";
      };
      policyPath = mkOption {
        type = types.str;
        default = "${config.xdg.configHome}/core-checkup/policy.json";
        defaultText = lib.literalExpression ''"''${config.xdg.configHome}/core-checkup/policy.json"'';
        description = "Operator-held policy file the checkup reads.";
      };
    };

    fieldCensus = {
      enable = mkEnableOption "the passive Field census snapshot callable service";
      observeOnly = mkOption {
        type = types.bool;
        default = true;
        description = "Pass --observe-only: snapshot only, never send HM summaries.";
      };
      recipientsPath = mkOption {
        type = types.str;
        default = "${config.xdg.configHome}/field-census/recipients.json";
        defaultText = lib.literalExpression ''"''${config.xdg.configHome}/field-census/recipients.json"'';
        description = "Census recipients configuration (read only when observeOnly is false).";
      };
    };

    fieldCheckupShadow = {
      enable = mkEnableOption "the passive three-aspect Field checkup callable service";
      rosterPath = mkOption {
        type = types.str;
        default = "${config.xdg.configHome}/field-checkup-shadow/roster.json";
        defaultText = lib.literalExpression ''"''${config.xdg.configHome}/field-checkup-shadow/roster.json"'';
        description = "Aspect roster the checkup assesses the census against.";
      };
    };

    fieldLunaResearch = {
      enable = mkEnableOption "the bounded read-only Field Luna source research callable service";
    };

  };

  config = mkMerge [
    {
      # A hand-made unit file of a declared name would make Home Manager's
      # link check refuse the generation; name it before that check runs.
      home.activation.fieldMonitoringHandMadeUnits = mkIf (enabledUnitNames != [ ]) (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          for unit in ${concatStringsSep " " enabledUnitNames}; do
            unit_path="${config.xdg.configHome}/systemd/user/$unit"
            if [ -e "$unit_path" ] || [ -L "$unit_path" ]; then
              case "$(readlink "$unit_path" 2>/dev/null || true)" in
                /nix/store/*-home-manager-files/*) ;;
                *) warnEcho "field-monitoring: hand-made unit $unit_path is still present; remove it (and its timers.target.wants link) before this declared unit can take its place" ;;
              esac
            fi
          done
        ''
      );
    }

    (mkIf cfg.coreCheckup.enable {
      assertions = [
        {
          assertion = cfg.coreCheckup.roster != null;
          message = "criomosHome.fieldMonitoring.coreCheckup.roster must be supplied when the core checkup is enabled.";
        }
      ];
      systemd.user.services.core-checkup = {
        Unit.Description = "Bounded monitoring-only core checkup from pinned primary source";
        Service = {
          Type = "oneshot";
          StateDirectory = "core-checkup";
          RuntimeMaxSec = "120s";
          TimeoutStartSec = "120s";
          MemoryMax = "256M";
          NoNewPrivileges = true;
          Environment = "PATH=${
            lib.makeBinPath [
              pkgs.nodejs
              pkgs.iputils
              pkgs.systemd
              codexPackage
              claudePackage
            ]
          }";
          ExecStartPre = "${pkgs.coreutils}/bin/test -r ${coreCheckupRoster}";
          ExecStart = "${nodeBin} ${coreCheckupSource}/tools/core-checkup.mjs ${coreCheckupRoster} ${cfg.coreCheckup.policyPath} %S/core-checkup/events.ndjson %S/core-checkup/state.json";
        };
      };
    })

    (mkIf cfg.fieldCensus.enable {
      systemd.user.services.field-census = {
        Unit.Description = "Passive Field census snapshot without messages";
        Service = {
          Type = "oneshot";
          WorkingDirectory = cfg.primaryRoot;
          Environment = [
            "FIELD_CENSUS_CONFIG=${cfg.fieldCensus.recipientsPath}"
            "FIELD_CENSUS_STATE=${config.xdg.stateHome}/field-census"
            "PATH=${
              lib.makeBinPath [
                pkgs.nodejs
                herdrPackage
                messengerCljPackage
                pkgs.systemd
                pkgs.coreutils
              ]
            }"
          ];
          ExecStart =
            "${nodeBin} ${fieldMonitoringSource}/tools/field-census-cycle.mjs"
            + lib.optionalString cfg.fieldCensus.observeOnly " --observe-only";
          TimeoutStartSec = "30s";
          MemoryMax = "256M";
          NoNewPrivileges = true;
          UMask = "0077";
        };
      };
    })

    (mkIf cfg.fieldCheckupShadow.enable {
      systemd.user.services.field-checkup-shadow = {
        Unit = {
          Description = "Passive three-aspect checkup from the Field census";
          After = [ "field-census.service" ];
        };
        Service = {
          Type = "oneshot";
          WorkingDirectory = cfg.primaryRoot;
          Environment = [
            "FIELD_CENSUS_STATE=${config.xdg.stateHome}/field-census"
            "FIELD_CHECKUP_ROSTER=${cfg.fieldCheckupShadow.rosterPath}"
            "FIELD_CHECKUP_STATE=${config.xdg.stateHome}/field-checkup-shadow"
          ];
          ExecStart = "${nodeBin} ${fieldMonitoringSource}/tools/field-checkup-shadow-cycle.mjs";
          TimeoutStartSec = "30s";
          MemoryMax = "256M";
          NoNewPrivileges = true;
          UMask = "0077";
        };
      };
    })

    (mkIf cfg.fieldLunaResearch.enable {
      systemd.user.services.field-luna-research = {
        Unit.Description = "Bounded read-only Field Luna source research";
        Service = {
          Type = "oneshot";
          WorkingDirectory = "${fieldSource}";
          Environment = [ "FIELD_PRIMARY_ROOT=${cfg.primaryRoot}" ];
          ExecStart = "${fieldLunaResearchRunner}/bin/field-luna-research-run --once";
          TimeoutStartSec = "610";
        };
      };
    })
  ];
}
