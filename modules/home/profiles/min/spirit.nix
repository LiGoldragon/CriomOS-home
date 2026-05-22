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
    genAttrs
    listToAttrs
    mapAttrsToList
    mkIf
    mkOption
    nameValuePair
    ;
  inherit (lib.types) enum listOf;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;

  availableVersions = [
    "v0.1.0"
    "v0.1.1"
  ];

  packageInputsByVersion = {
    "v0.1.0" = inputs."persona-spirit-v0-1-0";
    "v0.1.1" = inputs."persona-spirit-v0-1-1";
  };

  sanitizeVersion = builtins.replaceStrings [ "." ] [ "-" ];

  rootStateDirectory = "${config.home.homeDirectory}/.local/state/persona-spirit";
  legacyDatabasePath = "${rootStateDirectory}/persona-spirit.redb";

  deployedVersions = config.criomosHome.personaSpirit.deployedVersions;
  currentDefault = config.criomosHome.personaSpirit.currentDefault;

  makeDeployment =
    version:
    let
      packageInput = packageInputsByVersion.${version};
      commandLine = packageInput.packages.${system}.spirit;
      daemon = packageInput.packages.${system}.persona-spirit-daemon;
      safeVersion = sanitizeVersion version;
      stateDirectory = "${rootStateDirectory}/${version}";
      ordinarySocketPath = "${stateDirectory}/spirit.sock";
      ownerSocketPath = "${stateDirectory}/owner.sock";
      databasePath = "${stateDirectory}/persona-spirit.redb";
      configuration = ''("${ordinarySocketPath}" "${ownerSocketPath}" "${databasePath}" 384 None)'';
      initializeState = pkgs.writeShellScript "persona-spirit-${safeVersion}-state" ''
        set -eu

        version=${lib.escapeShellArg version}
        state_directory=${lib.escapeShellArg stateDirectory}
        ordinary_socket_path=${lib.escapeShellArg ordinarySocketPath}
        owner_socket_path=${lib.escapeShellArg ownerSocketPath}
        database_path=${lib.escapeShellArg databasePath}
        legacy_database_path=${lib.escapeShellArg legacyDatabasePath}

        ${pkgs.coreutils}/bin/mkdir -p "$state_directory"
        ${pkgs.coreutils}/bin/rm -f "$ordinary_socket_path" "$owner_socket_path"

        if [ "$version" = "v0.1.0" ] \
          && [ ! -e "$database_path" ] \
          && [ -e "$legacy_database_path" ]; then
          ${pkgs.coreutils}/bin/cp -p "$legacy_database_path" "$database_path"
        fi
      '';
      startDaemon = pkgs.writeShellScript "persona-spirit-daemon-${safeVersion}-start" ''
        exec ${daemon}/bin/persona-spirit-daemon '${configuration}'
      '';
      commandLineWrapper = pkgs.writeShellScriptBin "spirit-${version}" ''
        export PERSONA_SPIRIT_SOCKET=${lib.escapeShellArg ordinarySocketPath}
        export PERSONA_SPIRIT_OWNER_SOCKET=${lib.escapeShellArg ownerSocketPath}
        exec ${commandLine}/bin/spirit "$@"
      '';
    in
    {
      inherit
        commandLineWrapper
        databasePath
        initializeState
        ordinarySocketPath
        ownerSocketPath
        startDaemon
        stateDirectory
        ;
      serviceName = "persona-spirit-daemon-${version}";
      wrapperName = "spirit-${version}";
    };

  deployments = genAttrs deployedVersions makeDeployment;

  selectedDeployment =
    if builtins.elem currentDefault deployedVersions then
      deployments.${currentDefault}
    else
      throw "criomosHome.personaSpirit.currentDefault must be listed in deployedVersions";

  defaultCommandLine = pkgs.runCommand "spirit-current-${sanitizeVersion currentDefault}" { } ''
    mkdir -p "$out/bin"
    ln -s "${selectedDeployment.commandLineWrapper}/bin/${selectedDeployment.wrapperName}" "$out/bin/spirit"
  '';

  makeService =
    version: deployment:
    nameValuePair deployment.serviceName {
      Unit = {
        Description = "Persona-spirit daemon ${version}";
        Conflicts = [ "persona-spirit-daemon.service" ];
        After = [ "persona-spirit-daemon.service" ];
      };

      Service = {
        ExecStartPre = "${deployment.initializeState}";
        ExecStart = "${deployment.startDaemon}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
in
{
  options.criomosHome.personaSpirit = {
    deployedVersions = mkOption {
      type = listOf (enum availableVersions);
      default = availableVersions;
      description = "Persona-spirit versions deployed side by side in the user session.";
    };

    currentDefault = mkOption {
      type = enum availableVersions;
      default = "v0.1.0";
      description = "Persona-spirit version reached by the unsuffixed spirit command.";
    };
  };

  config = mkIf size.min {
    assertions = [
      {
        assertion = builtins.elem currentDefault deployedVersions;
        message = "criomosHome.personaSpirit.currentDefault must be one of deployedVersions.";
      }
      {
        assertion = lib.unique deployedVersions == deployedVersions;
        message = "criomosHome.personaSpirit.deployedVersions must not contain duplicates.";
      }
    ];

    home.packages = (map (version: deployments.${version}.commandLineWrapper) deployedVersions) ++ [
      defaultCommandLine
    ];

    systemd.user.services = listToAttrs (mapAttrsToList makeService deployments);
  };
}
