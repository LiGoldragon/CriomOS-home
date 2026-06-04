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
  pi-subagents = pkgs.callPackage ../../../../packages/pi-subagents { inherit inputs; };
  pi-continue = pkgs.callPackage ../../../../packages/pi-continue { inherit inputs; };
  pi-web-access = pkgs.callPackage ../../../../packages/pi-web-access { inherit inputs; };

  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  providerName = "criomos-local";
  defaultLocalModel = "gemma-4-26b-a4b";
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
    defaultProvider = providerName;
    defaultModel = defaultLocalModel;
    defaultThinkingLevel = "off";
    enabledModels =
      remoteOpenAiCodexModels ++ map (model: "${providerName}/${model.modelId}") inventory.models;
    theme = "criomos-dark";
    doubleEscapeAction = "tree";
    hideThinkingBlock = false;
    compaction = {
      enabled = true;
      reserveTokens = 32768;
      keepRecentTokens = 20000;
    };
    retry.enabled = true;
    packages = [
      "packages/pi-criomos"
      "packages/pi-linkup"
      "packages/pi-web-access"
      "packages/pi-subagents"
      "packages/pi-continue"
    ];
  };
in
lib.mkIf (size.min && endpointNode != null) {
  home.file.".local/share/criomos/pi/package".source = "${pi}/lib/pi-monorepo/packages/coding-agent";

  home.file.".pi/agent/packages/pi-criomos".source = "${pi-criomos}/share/pi-packages/pi-criomos";

  home.file.".pi/agent/packages/pi-linkup".source = "${pi-linkup}/share/pi-packages/pi-linkup";

  home.file.".pi/agent/packages/pi-subagents".source =
    "${pi-subagents}/share/pi-packages/pi-subagents";

  home.file.".pi/agent/packages/pi-continue".source = "${pi-continue}/share/pi-packages/pi-continue";

  home.file.".pi/agent/packages/pi-web-access".source =
    "${pi-web-access}/share/pi-packages/pi-web-access";

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
      "/packages" = "always";
    };
  };
}
