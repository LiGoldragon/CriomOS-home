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
  inherit (builtins)
    fromJSON
    readFile
    toString
    ;
  inherit (lib)
    mkIf
    mkOption
    ;
  inherit (lib.types) bool;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  agentPackage = inputs.agent.packages.${system}.default;
  spiritPackage = inputs.spirit.packages.${system}.default;

  inventory = fromJSON (readFile (inputs.criomos-lib + "/data/largeAI/llm.json"));
  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  providerName = "criomos-local";
  defaultLocalModel = "gemma-4-26b-a4b";
  localLlmApiKeyEnvironment = "LOCAL_LLM_API_KEY";
  localLlmGopassPath = "goldragon.criome/local-llm-api-token";
  localLlmEndpoint =
    if endpointNode != null then
      "http://${endpointNode.criomeDomainName}:${toString (inventory.serverPort or 11434)}/v1"
    else
      null;

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

  legacyStateDirectory = "${config.home.homeDirectory}/.local/state/persona-spirit";
  legacyCurrentDatabasePath = "${legacyStateDirectory}/v0.5.2/persona-spirit.redb";

  agentDaemonConfiguration = pkgs.runCommand "agent-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${agentPackage}/bin/agent-write-configuration \
      "(AgentConfigurationWriteRequest ${agentSocketPath} ${agentMetaSocketPath} 384 ${agentDatabasePath} [(ProviderSeed ${providerName} ${localLlmEndpoint} ${defaultLocalModel} ${localLlmApiKeyEnvironment})] $out/${agentConfigurationPath})" \
      > "$out/configuration-written.nota"
    test -s "$out/${agentConfigurationPath}"
  '';

  guardianAgentConfiguration =
    if endpointNode != null then
      "(Some (ConfigurationWriterGuardianAgent ${agentSocketPath} (Some ${providerName}) (Some ${defaultLocalModel}) 30000 256))"
    else
      "None";

  daemonConfiguration = pkgs.runCommand "spirit-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${spiritPackage}/bin/spirit-write-configuration \
      "(ConfigurationWriteRequest ${socketPath} (Some ${metaSocketPath}) ${databasePath} None ${guardianAgentConfiguration} $out/${configurationPath})" \
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

  agentCommandLineWrapper = pkgs.writeShellScriptBin "agent" ''
    export AGENT_SOCKET=${lib.escapeShellArg agentSocketPath}
    exec ${agentPackage}/bin/agent "$@"
  '';

  agentServiceWrapper = pkgs.writeShellScriptBin "agent-daemon-service" ''
    set -eu

    export ${localLlmApiKeyEnvironment}="$(${pkgs.gopass}/bin/gopass show -o ${lib.escapeShellArg localLlmGopassPath})"
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
    ]
    ++ lib.optionals (endpointNode != null) [ agentCommandLineWrapper ];

    home.activation.spiritState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${activateState}
    '';

    systemd.user.services =
      lib.optionalAttrs (endpointNode != null) {
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
          // lib.optionalAttrs (endpointNode != null) {
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
