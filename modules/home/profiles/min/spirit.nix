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
  spiritPackage = inputs.spirit.packages.${system}.default;

  providerName = "deepseek";
  defaultModel = "deepseek-v4-flash";
  # The guardian is a deliberate judge: a well-trained DeepSeek Pro at high
  # reasoning effort beats Flash on the discriminating admission cases
  # (missing-testimony, certainty over-claim) per the flash-vs-pro eval.
  guardianModel = "deepseek-v4-pro";
  providerEndpoint = "https://api.deepseek.com/v1";
  providerGopassPath = "platform.deepseek.com/api-key";

  stateDirectory = "${config.home.homeDirectory}/.local/state/spirit";
  socketPath = "${stateDirectory}/spirit.sock";
  metaSocketPath = "${stateDirectory}/meta-spirit.sock";
  databasePath = "${stateDirectory}/spirit.sema";
  configurationPath = "spirit.config.rkyv";

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
      > "$out/configuration-written.nota"
    test -s "$out/${agentConfigurationPath}"
  '';

  guardianAgentConfiguration = "(Some (${agentSocketPath} (Some ${providerName}) (Some ${guardianModel}) 180000 None))";

  daemonConfiguration = pkgs.runCommand "spirit-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${spiritPackage}/bin/spirit-write-configuration \
      "(ConfigurationWriteRequest (${socketPath} (Some ${metaSocketPath}) ${databasePath} None ${guardianAgentConfiguration} $out/${configurationPath}))" \
      > "$out/configuration-written.nota"
    test -s "$out/${configurationPath}"
  '';

  migrateState = ''
    ${spiritPackage}/bin/spirit-migrate-store \
      "($database_path)"
  '';

  activateState = pkgs.writeShellScript "spirit-activation-state" ''
    set -eu

    state_directory=${lib.escapeShellArg stateDirectory}
    agent_state_directory=${lib.escapeShellArg agentStateDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$state_directory"
    ${pkgs.coreutils}/bin/mkdir -p "$agent_state_directory"
  '';

  initializeAgentState = pkgs.writeShellScript "agent-startup-state" ''
    set -eu

    agent_state_directory=${lib.escapeShellArg agentStateDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$agent_state_directory"
    ${pkgs.coreutils}/bin/rm -f \
      ${lib.escapeShellArg agentSocketPath} \
      ${lib.escapeShellArg agentMetaSocketPath}
  '';

  initializeState = pkgs.writeShellScript "spirit-startup-state" ''
    set -eu

    state_directory=${lib.escapeShellArg stateDirectory}
    database_path=${lib.escapeShellArg databasePath}

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

  metaSpiritCommandLineWrapper = pkgs.writeShellScriptBin "meta-spirit" ''
    export SPIRIT_META_SOCKET=${lib.escapeShellArg metaSocketPath}
    exec ${spiritPackage}/bin/meta-spirit "$@"
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
      default = true;
      description = "Deploy the schema-derived Spirit CLI and user-session daemon.";
    };
  };

  config = mkIf (size.min && config.criomosHome.spirit.enable) {
    home.packages = [
      commandLineWrapper
      metaSpiritCommandLineWrapper
      agentCommandLineWrapper
    ];

    home.activation.spiritState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${activateState}
    '';

    systemd.user.services = {
      agent-daemon = {
        Unit = {
          Description = "Agent schema-derived daemon";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 5;
        };

        Service = {
          ExecStartPre = "${initializeAgentState}";
          ExecStart = "${agentServiceWrapper}/bin/agent-daemon-service";
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
          After = [ "agent-daemon.service" ];
          Wants = [ "agent-daemon.service" ];
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
  };
}
