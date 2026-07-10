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
  inherit (user) size;

  inventory = fromJSON (readFile (inputs.criomos-lib + "/data/largeAI/llm.json"));
  pi = pkgs.callPackage ../../../../packages/pi { inherit inputs; };
  pi-criomos = pkgs.callPackage ../../../../packages/pi-criomos { };
  pi-linkup = pkgs.callPackage ../../../../packages/pi-linkup { inherit inputs; };
  pi-subagents-tintinweb = pkgs.callPackage ../../../../packages/pi-subagents-tintinweb {
    inherit inputs;
  };
  pi-continue = pkgs.callPackage ../../../../packages/pi-continue { inherit inputs; };
  pi-session-namer = pkgs.callPackage ../../../../packages/pi-session-namer { inherit inputs; };
  piPackageHomePath = "$HOME/.local/share/criomos/pi/package";

  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  providerName = "criomos-local";
  defaultOpenAiCodexModel = "gpt-5.5";
  localLlmApiKeyCommand = "!gopass show -o goldragon.criome/local-llm-api-token";
  legacyLocalProviderNames = [
    "prometheus"
    "criomos-largeai"
  ];
  remoteOpenAiCodexModels = [
    "openai-codex/gpt-5.5"
    "openai-codex/gpt-5.4-mini"
  ];
  piCriomosPackage = {
    source = "packages/pi-criomos";
    extensions = [ "extensions/live-theme-control.ts" ];
  };
  normalPiPackages = [
    piCriomosPackage
    "packages/pi-linkup"
    "packages/pi-subagents-tintinweb"
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

  piModelsConfig = {
    providers.${providerName} = {
      api = "openai-completions";
      baseUrl = "http://${endpointNode.criomeDomainName}:${toString (inventory.serverPort or 11434)}/v1";
      # Pi requires an apiKey field for custom providers. The actual
      # Prometheus llama-router token is resolved at request time from
      # the standard local gopass entry; the token bytes never enter Nix.
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

  piAuthConfig = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = localProviderAuth;
    }) ([ providerName ] ++ legacyLocalProviderNames)
  );

  piSettingsConfig = {
    defaultProvider = "openai-codex";
    defaultModel = defaultOpenAiCodexModel;
    defaultThinkingLevel = "high";
    enabledModels =
      remoteOpenAiCodexModels ++ map (model: "${providerName}/${model.modelId}") inventory.models;
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
  };

  piTestingSettingsConfig = piSettingsConfig;
in
lib.mkIf (size.min && endpointNode != null) {
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

  home.file.".pi/agent/bin/pi".source = "${pi}/bin/pi";
  home.file.".pi/agent/bin/pi".force = true;

  home.file.".pi/agent/SYSTEM.md".source =
    "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md";

  home.file.".pi/agent/packages/pi-criomos".source = "${pi-criomos}/share/pi-packages/pi-criomos";
  home.file.".pi/agent/packages/pi-criomos".force = true;

  home.file.".pi/agent/packages/pi-linkup".source = "${pi-linkup}/share/pi-packages/pi-linkup";
  home.file.".pi/agent/packages/pi-linkup".force = true;

  home.file.".pi/agent/packages/pi-subagents-tintinweb".source =
    "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb";
  home.file.".pi/agent/packages/pi-subagents-tintinweb".force = true;

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

  home.file.".pi-testing/agent/packages/pi-subagents-tintinweb".source =
    "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb";
  home.file.".pi-testing/agent/packages/pi-subagents-tintinweb".force = true;

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
    };
  };
}
