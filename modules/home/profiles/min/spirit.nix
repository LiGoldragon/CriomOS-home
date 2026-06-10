{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    ;
  inherit (lib.types) bool;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  spiritPackage = inputs.spirit.packages.${system}.default;

  stateDirectory = "${config.home.homeDirectory}/.local/state/spirit";
  socketPath = "${stateDirectory}/spirit.sock";
  metaSocketPath = "${stateDirectory}/meta-spirit.sock";
  databasePath = "${stateDirectory}/spirit.sema";
  configurationPath = "spirit.config.rkyv";

  legacyStateDirectory = "${config.home.homeDirectory}/.local/state/persona-spirit";
  legacyCurrentDatabasePath = "${legacyStateDirectory}/v0.5.2/persona-spirit.redb";

  daemonConfiguration = pkgs.runCommand "spirit-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${spiritPackage}/bin/spirit-write-configuration \
      "(ConfigurationWriteRequest ${socketPath} (Some ${metaSocketPath}) ${databasePath} None $out/${configurationPath})" \
      > "$out/configuration-written.nota"
    test -s "$out/${configurationPath}"
  '';

  migrateState = ''
    if [ ! -e "$database_path" ] && [ -e "$legacy_database_path" ]; then
      ${spiritPackage}/bin/spirit-migrate-production \
        "($legacy_database_path $database_path)"
    fi
    ${spiritPackage}/bin/spirit-upgrade-store \
      "($database_path)"
  '';

  activateState = pkgs.writeShellScript "spirit-activation-state" ''
    set -eu

    state_directory=${lib.escapeShellArg stateDirectory}
    database_path=${lib.escapeShellArg databasePath}
    legacy_database_path=${lib.escapeShellArg legacyCurrentDatabasePath}

    ${pkgs.coreutils}/bin/mkdir -p "$state_directory"

    ${migrateState}
  '';

  initializeState = pkgs.writeShellScript "spirit-startup-state" ''
    set -eu

    state_directory=${lib.escapeShellArg stateDirectory}
    database_path=${lib.escapeShellArg databasePath}
    legacy_database_path=${lib.escapeShellArg legacyCurrentDatabasePath}

    ${pkgs.coreutils}/bin/mkdir -p "$state_directory"
    ${pkgs.coreutils}/bin/rm -f \
      ${lib.escapeShellArg socketPath} \
      ${lib.escapeShellArg metaSocketPath}

    ${migrateState}
  '';

  commandLineWrapper = pkgs.writeShellScriptBin "spirit" ''
    export SPIRIT_SOCKET=${lib.escapeShellArg socketPath}
    exec ${spiritPackage}/bin/spirit "$@"
  '';
in
{
  options.criomosHome.spirit = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Deploy the schema-derived Spirit CLI and user-session daemon.";
    };
  };

  config = mkIf (size.min && config.criomosHome.spirit.enable) {
    home.packages = [ commandLineWrapper ];

    home.activation.spiritState = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${activateState}
    '';

    systemd.user.services.spirit-daemon = {
      Unit = {
        Description = "Spirit schema-derived daemon";
        Conflicts = [
          "persona-spirit-daemon.service"
          "persona-spirit-daemon-v0.1.0.service"
          "persona-spirit-daemon-v0.1.1.service"
          "persona-spirit-daemon-v0.2.0.service"
          "persona-spirit-daemon-v0.3.0.service"
          "persona-spirit-daemon-v0.4.0.service"
          "persona-spirit-daemon-v0.4.1.service"
          "persona-spirit-daemon-v0.4.2.service"
          "persona-spirit-daemon-v0.5.0.service"
          "persona-spirit-daemon-v0.5.1.service"
          "persona-spirit-daemon-v0.5.2.service"
          "persona-spirit-daemon-next.service"
        ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        ExecStartPre = "${initializeState}";
        ExecStart = "${spiritPackage}/bin/spirit-daemon ${daemonConfiguration}/${configurationPath}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
