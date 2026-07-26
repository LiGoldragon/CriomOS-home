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
  spiritJudgePackage = inputs.spirit-judge.packages.${system}.default;
  spiritJudgeConfig = inputs.spirit-judge-config;
  codexCliPackage = inputs.codex-cli.packages.${system}.default;

  # These values configure the retained agent daemon only. Spirit judgment is
  # served by the separate OpenAI Codex adapter below.
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
  socketPath = "${stateDirectory}/spirit.sock";
  metaSocketPath = "${stateDirectory}/meta-spirit.sock";
  spiritJudgeSocketPath = "${stateDirectory}/spirit-judge.sock";
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

  # The compatibility-named configuration field now carries only Spirit's
  # typed judge socket and timeout. Provider/model selection belongs to the
  # adapter service, not the Spirit daemon, so the legacy provider fields stay
  # empty and cannot silently select a fallback judge.
  guardianAgentConfiguration = "(Some (${spiritJudgeSocketPath} None None 180000 None))";

  # AuthorizationMode gates the separate criome/mirror path. `Gating` remains
  # Spirit's default; judge admission is independently mandatory through the
  # configured typed judge socket.
  authorizationMode = "Gating";

  daemonConfiguration = pkgs.runCommand "spirit-daemon-configuration" { } ''
    set -eu

    mkdir -p "$out"
    ${spiritPackage}/bin/spirit-write-configuration \
      "(ConfigurationWriteRequest (${socketPath} (Some ${metaSocketPath}) ${databasePath} None ${authorizationMode} ${guardianAgentConfiguration} $out/${configurationPath}))" \
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

  initializeJudgeState = pkgs.writeShellScript "spirit-judge-startup-state" ''
    set -eu

    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg stateDirectory}
    ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg spiritJudgeSocketPath}
  '';

  # spirit-judge takes exactly one argument: a NOTA payload carrying its
  # fully typed `serve` configuration (the workspace single-argument
  # executable rule; see standards/standard-component-architecture.md). This
  # mirrors how `spirit-write-configuration` above is invoked: one binary name,
  # one double-quoted NOTA record as a single shell argument.
  spiritJudgeServeRequest = "(Serve (${spiritJudgeSocketPath} ${spiritJudgeConfig} OpenAiCodex gpt-5.6-terra (Some Medium) 180000 None None (Some codex-login) (Some ${pkgs.util-linux}/bin/setsid) (Some ${codexCliPackage}/bin/codex) None))";

  spiritJudgeServiceWrapper = pkgs.writeShellScriptBin "spirit-judge-daemon-service" ''
    set -eu

    # OpenAI Codex owns the authenticated session and receives no copied token.
    # The reference is policy data only; the executable resolves it at runtime.
    exec ${spiritJudgePackage}/bin/spirit-judge \
      ${lib.escapeShellArg spiritJudgeServeRequest}
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
      spirit-judge = {
        Unit = {
          Description = "Spirit fail-closed judgment adapter";
          StartLimitIntervalSec = 60;
          StartLimitBurst = 5;
        };

        Service = {
          ExecStartPre = "${initializeJudgeState}";
          ExecStart = "${spiritJudgeServiceWrapper}/bin/spirit-judge-daemon-service";
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
          ExecStart = "${spiritPackage}/bin/spirit-daemon ${daemonConfiguration}/${configurationPath}";
          Restart = "on-failure";
          RestartSec = "2s";
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
