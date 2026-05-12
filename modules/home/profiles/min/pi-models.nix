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
  pi-linkup = pkgs.callPackage ../../../../packages/pi-linkup { };

  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  routerNode = lib.findFirst (node: node.typeIs.largeAiRouter or false) null clusterNodes;
  largeAiNode = lib.findFirst (node: node.behavesAs.largeAi or false) null clusterNodes;
  endpointNode = if routerNode != null then routerNode else largeAiNode;
  providerName = "criomos-local";

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
      # Pi requires an API key value for custom providers. The llama.cpp
      # router does not require one unless /var/lib/llama/api-key is non-empty.
      apiKey = "sk-no-key-required";
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

  piSettingsConfig = {
    defaultProvider = providerName;
    enabledModels = map (model: "${providerName}/${model.modelId}") inventory.models;
    packages = [
      "packages/pi-linkup"
    ];
  };
in
lib.mkIf (size.min && endpointNode != null) {
  home.file.".local/share/criomos/pi/package".source = "${pi}/lib/pi-monorepo/packages/coding-agent";

  home.file.".pi/agent/packages/pi-linkup".source = "${pi-linkup}/share/pi-packages/pi-linkup";

  home.activation.mergePiModels = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/models.json";
    declared = piModelsConfig;
  };

  home.activation.mergePiSettings = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.pi/agent/settings.json";
    declared = piSettingsConfig;
    modes = {
      "/enabledModels" = "always";
      "/packages" = "always";
    };
  };
}
