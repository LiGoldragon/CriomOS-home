{
  config,
  inputs,
  lib,
  pkgs,
  horizon,
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
  agentPackage = inputs.agent.packages.${system}.default;
  serviceName =
    service:
    if builtins.isString service then
      service
    else if builtins.isAttrs service then
      let
        names = builtins.attrNames service;
      in
      if builtins.length names == 1 then builtins.head names else null
    else
      null;
  isPersonaDevelopment = builtins.any (service: serviceName service == "PersonaDevelopment") (
    horizon.node.services or [ ]
  );

  # These values configure the retained agent daemon only. The maintained
  # Spirit composition owns the separate judgment adapter and provider.
  providerName = "deepseek";
  defaultModel = "deepseek-v4-flash";
  providerEndpoint = "https://api.deepseek.com/v1";
  providerGopassPath = "platform.deepseek.com/api-key";

  # The agent daemon resolves its own provider credential at runtime. No secret
  # value is embedded in this Nix configuration.
  agentServicePath = lib.concatStringsSep ":" [
    "${config.home.homeDirectory}/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "/run/wrappers/bin"
  ];

  stateDirectory = "${config.home.homeDirectory}/.local/state/spirit";
  spiritArtifacts = inputs.spirit.lib.${system}.mkUserServiceArtifacts {
    inherit stateDirectory;
  };
  inherit (spiritArtifacts)
    activateState
    commandLineWrapper
    daemonServiceWrapper
    initializeJudgeState
    initializeState
    judgeServiceWrapper
    metaSpiritCommandLineWrapper
    ;

  agentStateDirectory = "${config.home.homeDirectory}/.local/state/agent";
  agentSocketPath = "${agentStateDirectory}/agent.sock";
  agentMetaSocketPath = "${agentStateDirectory}/agent-meta.sock";
  agentDatabasePath = "${agentStateDirectory}/agent.sema";
  agentConfigurationPath = "agent.config.rkyv";

  agentDaemonConfiguration = pkgs.runCommand "agent-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${agentPackage}/bin/agent-write-configuration \
      "(AgentConfigurationWriteRequest (${agentSocketPath} ${agentMetaSocketPath} 384 ${agentDatabasePath} [(ProviderSeed (${providerName} ${providerEndpoint} ${defaultModel} (Gopass ${providerGopassPath})))] $out/${agentConfigurationPath}))" \
      > "$out/configuration-written.dotos"
    test -s "$out/${agentConfigurationPath}"
  '';

  activateAgentState = pkgs.writeShellScript "agent-activation-state" ''
    set -eu

    agent_state_directory=${lib.escapeShellArg agentStateDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$agent_state_directory"
  '';

  migrateObsoleteSpiritJudgeOverride = pkgs.writeShellApplication {
    name = "migrate-obsolete-spirit-judge-override";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./migrate-obsolete-spirit-judge-override.sh;
  };

  obsoleteSpiritJudgeOverride = "${config.xdg.configHome}/systemd/user/spirit-judge.service.d/override.conf";

  initializeAgentState = pkgs.writeShellScript "agent-startup-state" ''
    set -eu

    agent_state_directory=${lib.escapeShellArg agentStateDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$agent_state_directory"
    ${pkgs.coreutils}/bin/rm -f \
      ${lib.escapeShellArg agentSocketPath} \
      ${lib.escapeShellArg agentMetaSocketPath}
  '';

  agentCommandLineWrapper = pkgs.writeShellScriptBin "agent" ''
    export AGENT_SOCKET=${lib.escapeShellArg agentSocketPath}
    exec ${agentPackage}/bin/agent "$@"
  '';

  agentServiceWrapper = pkgs.writeShellScriptBin "agent-daemon-service" ''
    set -eu

    exec ${agentPackage}/bin/agent-daemon ${agentDaemonConfiguration}/${agentConfigurationPath}
  '';
in
{
  options.criomosHome.spirit = {
    enable = mkOption {
      type = bool;
      default = isPersonaDevelopment;
      description = "Deploy the schema-derived Spirit CLI and user-session daemons only on a Horizon PersonaDevelopment node.";
    };
  };

  config = mkIf (size.min && isPersonaDevelopment && config.criomosHome.spirit.enable) {
    home.packages = [
      commandLineWrapper
      metaSpiritCommandLineWrapper
      agentCommandLineWrapper
    ];

    home.activation.spiritState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${activateState}
      $DRY_RUN_CMD ${activateAgentState}
    '';

    # One historical, unmanaged drop-in shadows the generated judge ExecStart
    # with a collected package path. Remove only that exact stale shape after
    # the new generation is linked and before Home Manager reloads systemd.
    home.activation.removeObsoleteSpiritJudgeOverride =
      lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ]
        ''
          $DRY_RUN_CMD ${migrateObsoleteSpiritJudgeOverride}/bin/migrate-obsolete-spirit-judge-override \
            ${lib.escapeShellArg obsoleteSpiritJudgeOverride}
        '';

    systemd.user.services = {
      spirit-judge = {
        Unit = {
          Description = "Spirit fail-closed judgment adapter";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 5;
        };

        Service = {
          ExecStartPre = "${initializeJudgeState}";
          ExecStart = "${judgeServiceWrapper}/bin/spirit-judge-daemon-service";
          Restart = "on-failure";
          RestartSec = "2s";
        };

        Install.WantedBy = [ "default.target" ];
      };

      agent-daemon = {
        Unit = {
          Description = "Agent schema-derived daemon";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 5;
        };

        Service = {
          ExecStartPre = "${initializeAgentState}";
          ExecStart = "${agentServiceWrapper}/bin/agent-daemon-service";
          Environment = [ "PATH=${agentServicePath}" ];
          Restart = "on-failure";
          RestartSec = "2s";
        };

        Install.WantedBy = [ "default.target" ];
      };
    }
    // {
      spirit-daemon = {
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
        }
        // {
          After = [ "spirit-judge.service" ];
          Requires = [ "spirit-judge.service" ];
        };

        Service = {
          ExecStartPre = "${initializeState}";
          ExecStart = "${daemonServiceWrapper}/bin/spirit-daemon-service";
          Restart = "on-failure";
          RestartSec = "2s";
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
