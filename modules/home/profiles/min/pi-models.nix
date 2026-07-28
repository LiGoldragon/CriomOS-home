{
  lib,
  pkgs,
  inputs,
  horizon,
  user,
  hexis,
  ...
}:
let
  inherit (builtins)
    fromJSON
    map
    readFile
    toString
    ;
  inventory = fromJSON (readFile (inputs.criomos-lib + "/data/largeAI/llm.json"));
  pi = pkgs.callPackage ../../../../packages/pi { inherit inputs; };
  pi-criomos = pkgs.callPackage ../../../../packages/pi-criomos { };
  pi-linkup = pkgs.callPackage ../../../../packages/pi-linkup { inherit inputs; };
  pi-subagents = pkgs.callPackage ../../../../packages/pi-subagents {
    inherit inputs;
  };
  agent-intercom = pkgs.callPackage ../../../../packages/agent-intercom { inherit inputs; };
  pi-continue = pkgs.callPackage ../../../../packages/pi-continue { inherit inputs; };
  pi-session-namer = pkgs.callPackage ../../../../packages/pi-session-namer { inherit inputs; };
  piPackageHomePath = "$HOME/.local/share/criomos/pi/package";

  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  providerName = "criomos-local";
  defaultOpenAiCodexModel = "gpt-5.6-sol";
  localLlmApiKeyCommand = "!gopass show -o goldragon.criome/local-llm-api-token";
  legacyLocalProviderNames = [
    "prometheus"
    "criomos-largeai"
  ];
  remoteOpenAiCodexModels = [
    "openai-codex/gpt-5.6-sol"
    "openai-codex/gpt-5.6-terra"
    "openai-codex/gpt-5.6-luna"
  ];
  piCriomosPackage = {
    source = "packages/pi-criomos";
    extensions = [ "extensions/live-theme-control.ts" ];
  };
  normalPiPackages = [
    piCriomosPackage
    "packages/pi-linkup"
    "packages/pi-subagents"
    "packages/agent-intercom-pi"
    "packages/agent-intercom-orchestrator"
    "packages/pi-continue"
    "packages/pi-session-namer"
  ];

  mkPiModel = model: {
    id = model.modelId;
    name = model.descriptor or model.modelId;
    reasoning = model.reasoning or false;
    input = [ "text" ];
    contextWindow = model.contextWindow or (model.ctxSize or 128000);
    maxTokens = model.maxTokens or 4096;
  };

  piModelsConfig = lib.optionalAttrs (endpointNode != null) {
    providers.${providerName} = {
      api = "openai-completions";
      baseUrl = "http://${endpointNode.criomeDomainName}:${toString (inventory.serverPort or 11434)}/v1";
      # Pi requires an apiKey field for custom providers. The actual local
      # llama-router token is resolved at request time; token bytes never
      # enter Nix, the store, or generated configuration.
      apiKey = localLlmApiKeyCommand;
      compat = {
        supportsStore = false;
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
        supportsUsageInStreaming = false;
        maxTokensField = "max_tokens";
        supportsStrictMode = false;
        supportsLongCacheRetention = false;
      };
      models = map mkPiModel inventory.models;
    };
  };

  localProviderAuth = {
    type = "api_key";
    key = localLlmApiKeyCommand;
  };

  piAuthConfig = lib.optionalAttrs (endpointNode != null) (
    builtins.listToAttrs (
      map (name: {
        inherit name;
        value = localProviderAuth;
      }) ([ providerName ] ++ legacyLocalProviderNames)
    )
  );

  piIntercomConfig = {
    enabled = true;
    brokerCommand = "${pkgs.nodejs}/bin/node";
    brokerArgs = [
      "${agent-intercom}/share/agent-intercom/pi/node_modules/tsx/dist/cli.mjs"
    ];
    confirmSend = false;
    inboundTrigger = "always";
    replyHint = true;
    legacyTool = false;
  };

  piSubagentsConfigFile = pkgs.writeText "pi-subagents-config.json" (
    builtins.toJSON {
      toolDescriptionMode = "compact";
      asyncByDefault = true;
      proactiveSkillSubagents = false;
    }
  );

  piSettingsConfig = {
    defaultProvider = "openai-codex";
    defaultModel = defaultOpenAiCodexModel;
    defaultThinkingLevel = "high";
    enabledModels =
      remoteOpenAiCodexModels
      ++ lib.optionals (endpointNode != null) (
        map (model: "${providerName}/${model.modelId}") inventory.models
      );
    theme = "criomos-light/criomos-dark";
    doubleEscapeAction = "tree";
    hideThinkingBlock = false;
    compaction = {
      enabled = true;
      reserveTokens = 32768;
      keepRecentTokens = 20000;
    };
    retry.enabled = true;
    transport = "websocket";
    packages = normalPiPackages;
    subagents.disableBuiltins = true;
  };

  piTestingSettingsConfig = piSettingsConfig;
in
# Pi is a user-profile surface, not a host service capability.  In particular,
# an edge user environment must retain its .pi and .pi-testing state even when
# the host does not run Agent Intercom locally.  The projected node roles still
# determine whether a local provider record is available above.
lib.mkIf user.size.min {
  home.activation.preparePiPackageSymlink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    if [ -d "${piPackageHomePath}" ] && [ ! -L "${piPackageHomePath}" ]; then
      if ${pkgs.jq}/bin/jq -e '.name == "@earendil-works/pi-coding-agent"' \
        "${piPackageHomePath}/package.json" >/dev/null; then
        migration_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/criomos/pi-package-migrations"
        migration_timestamp="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
        migration_target="$migration_directory/package.$migration_timestamp"
        migration_counter=0

        while [ -e "$migration_target" ]; do
          migration_counter=$((migration_counter + 1))
          migration_target="$migration_directory/package.$migration_timestamp.$migration_counter"
        done

        run ${pkgs.coreutils}/bin/mkdir -p "$migration_directory"
        run ${pkgs.coreutils}/bin/mv "${piPackageHomePath}" "$migration_target"
      else
        echo "Existing Pi package path is a directory without the expected Pi package identity: ${piPackageHomePath}" >&2
        exit 1
      fi
    fi
  '';

  home.file.".local/share/criomos/pi/package".source = "${pi}/lib/pi-monorepo/packages/coding-agent";
  home.file.".local/share/criomos/pi/package".force = true;

  home.file.".pi/agent/SYSTEM.md".source =
    "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md";

  home.file.".pi/agent/packages/pi-criomos".source = "${pi-criomos}/share/pi-packages/pi-criomos";
  home.file.".pi/agent/packages/pi-criomos".force = true;

  home.file.".pi/agent/packages/pi-linkup".source = "${pi-linkup}/share/pi-packages/pi-linkup";
  home.file.".pi/agent/packages/pi-linkup".force = true;

  home.file.".pi/agent/packages/pi-subagents".source =
    "${pi-subagents}/share/pi-packages/pi-subagents";
  home.file.".pi/agent/packages/pi-subagents".force = true;
  home.file.".pi/agent/extensions/subagent/config.json".source = piSubagentsConfigFile;
  home.file.".pi/agent/extensions/subagent/config.json".force = true;

  # Pi resolves the pinned Agent Intercom adapter before historic extension
  # locations. The broker protocol remains local at broker.sock.
  home.sessionVariables.PI_INTERCOM_EXTENSION_DIR = "${agent-intercom}/share/agent-intercom/pi";

  home.file.".pi/agent/packages/pi-continue".source = "${pi-continue}/share/pi-packages/pi-continue";
  home.file.".pi/agent/packages/pi-continue".force = true;

  home.file.".pi/agent/packages/pi-session-namer".source =
    "${pi-session-namer}/share/pi-packages/pi-session-namer";
  home.file.".pi/agent/packages/pi-session-namer".force = true;

  home.file.".pi-testing/agent/SYSTEM.md".source =
    "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md";

  home.file.".pi-testing/agent/packages/pi-criomos".source =
    "${pi-criomos}/share/pi-packages/pi-criomos";
  home.file.".pi-testing/agent/packages/pi-criomos".force = true;

  home.file.".pi-testing/agent/packages/pi-linkup".source =
    "${pi-linkup}/share/pi-packages/pi-linkup";
  home.file.".pi-testing/agent/packages/pi-linkup".force = true;

  home.file.".pi-testing/agent/packages/pi-subagents".source =
    "${pi-subagents}/share/pi-packages/pi-subagents";
  home.file.".pi-testing/agent/packages/pi-subagents".force = true;
  home.file.".pi-testing/agent/extensions/subagent/config.json".source = piSubagentsConfigFile;
  home.file.".pi-testing/agent/extensions/subagent/config.json".force = true;

  home.file.".pi-testing/agent/packages/pi-continue".source =
    "${pi-continue}/share/pi-packages/pi-continue";
  home.file.".pi-testing/agent/packages/pi-continue".force = true;

  home.file.".pi-testing/agent/packages/pi-session-namer".source =
    "${pi-session-namer}/share/pi-packages/pi-session-namer";
  home.file.".pi-testing/agent/packages/pi-session-namer".force = true;

  home.activation.mergePiModels = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/models.json";
    declared = piModelsConfig;
  };

  home.activation.mergePiAuth = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/auth.json";
    declared = piAuthConfig;
    modes = builtins.listToAttrs (
      map (name: {
        name = "/${name}";
        value = "always";
      }) ([ providerName ] ++ legacyLocalProviderNames)
    );
  };

  home.activation.mergePiIntercomConfig = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/intercom/config.json";
    declared = piIntercomConfig;
    modes = {
      "/enabled" = "always";
    };
  };

  home.activation.mergePiSettings = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/settings.json";
    declared = piSettingsConfig;
    modes = {
      "/defaultProvider" = "always";
      "/defaultModel" = "always";
      "/defaultThinkingLevel" = "always";
      "/enabledModels" = "always";
      "/theme" = "always";
      "/doubleEscapeAction" = "always";
      "/compaction" = "always";
      "/transport" = "always";
      "/packages" = "always";
      "/subagents/disableBuiltins" = "always";
    };
  };

  home.activation.mergePiTestingModels = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi-testing/agent/models.json";
    declared = piModelsConfig;
  };

  home.activation.mergePiTestingAuth = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi-testing/agent/auth.json";
    declared = piAuthConfig;
    modes = builtins.listToAttrs (
      map (name: {
        name = "/${name}";
        value = "always";
      }) ([ providerName ] ++ legacyLocalProviderNames)
    );
  };

  home.activation.mergePiTestingIntercomConfig = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi-testing/agent/intercom/config.json";
    declared = piIntercomConfig;
    modes = {
      "/enabled" = "always";
    };
  };

  home.activation.mergePiTestingSettings = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi-testing/agent/settings.json";
    declared = piTestingSettingsConfig;
    modes = {
      "/defaultProvider" = "always";
      "/defaultModel" = "always";
      "/defaultThinkingLevel" = "always";
      "/enabledModels" = "always";
      "/theme" = "always";
      "/doubleEscapeAction" = "always";
      "/compaction" = "always";
      "/transport" = "always";
      "/packages" = "always";
      "/subagents/disableBuiltins" = "always";
    };
  };
}
