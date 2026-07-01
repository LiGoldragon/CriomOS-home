{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-linkup = inputs.self.packages.${system}.pi-linkup;
  pi-subagents = inputs.self.packages.${system}.pi-subagents;
  pi-subagents-tintinweb = inputs.self.packages.${system}.pi-subagents-tintinweb;
  pi-continue = inputs.self.packages.${system}.pi-continue;
  piLinkupPackage = ../../packages/pi-linkup/default.nix;
  piSubagentsPackage = ../../packages/pi-subagents/default.nix;
  piSubagentsTintinwebPackage = ../../packages/pi-subagents-tintinweb/default.nix;
  piContinuePackage = ../../packages/pi-continue/default.nix;
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
in
pkgs.runCommand "pi-harness-profile"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    test -f "${pi-linkup}/share/pi-packages/pi-linkup/package.json"
    test -d "${pi-linkup}/share/pi-packages/pi-linkup/node_modules/@aliou/pi-utils-ui"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/index.ts"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    test "$(wc -l < "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md")" -le 150
    grep -F 'Clarify UI is explicit opt-in' "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    ! grep -F 'Chains default to clarify mode' "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    test -f "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb/src/index.ts"
    test -d "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb/node_modules/@sinclair/typebox"
    test -d "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb/node_modules/croner"
    test -d "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb/node_modules/nanoid"
    jq -e '.name == "@tintinweb/pi-subagents" and .version == "0.13.0" and .pi.extensions == ["./src/index.ts"]' \
      "${pi-subagents-tintinweb}/share/pi-packages/pi-subagents-tintinweb/package.json"
    test -f "${pi-continue}/share/pi-packages/pi-continue/extensions/continue/index.ts"
    test -f "${pi-continue}/share/pi-packages/pi-continue/assets/user/continuation_base.md"

    test -f "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-dark.json"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-light.json"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/operator-safety.ts"
    jq -e '.pi.extensions == ["./src/extensions/theme-switcher.ts"]' \
      "${pi-criomos}/share/pi-packages/pi-criomos/package.json"
    grep -F 'path.join(stateDirectory, "chroma", "current-mode")' \
      "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"
    grep -F 'context.ui.setTheme(nextTheme)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"
    jq -e '.name == "criomos-dark" and (.colors | length == 51)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-dark.json"
    jq -e '.name == "criomos-light" and (.colors | length == 51)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-light.json"

    grep -F 'inputs.pi-linkup-src' ${piLinkupPackage}
    grep -F 'inputs.pi-utils-ui-src' ${piLinkupPackage}
    grep -F 'inputs.pi-subagents-src' ${piSubagentsPackage}
    grep -F 'inputs.pi-subagents-tintinweb-src' ${piSubagentsTintinwebPackage}
    grep -F 'inputs.pi-subagents-tintinweb-typebox-src' ${piSubagentsTintinwebPackage}
    grep -F 'inputs.pi-subagents-tintinweb-croner-src' ${piSubagentsTintinwebPackage}
    grep -F 'inputs.pi-subagents-tintinweb-nanoid-src' ${piSubagentsTintinwebPackage}
    grep -F 'inputs.pi-continue-src' ${piContinuePackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piLinkupPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piSubagentsPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piSubagentsTintinwebPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piContinuePackage}

    grep -F 'defaultProvider = "openai-codex";' ${piModelsModule}
    grep -F 'defaultOpenAiCodexModel = "gpt-5.5";' ${piModelsModule}
    grep -F 'defaultModel = defaultOpenAiCodexModel;' ${piModelsModule}
    grep -F 'defaultThinkingLevel = "high";' ${piModelsModule}
    grep -F '"openai-codex/gpt-5.4-mini"' ${piModelsModule}
    grep -F 'localLlmApiKeyCommand = "!gopass show -o goldragon.criome/local-llm-api-token";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi/agent/auth.json";' ${piModelsModule}
    grep -F 'theme = "criomos-dark";' ${piModelsModule}
    grep -F 'doubleEscapeAction = "tree";' ${piModelsModule}
    grep -F 'enabled = true;' ${piModelsModule}
    grep -F 'reserveTokens = 32768;' ${piModelsModule}
    grep -F 'keepRecentTokens = 20000;' ${piModelsModule}
    grep -F '"/compaction" = "always";' ${piModelsModule}
    grep -F '"packages/pi-criomos"' ${piModelsModule}
    grep -F '"packages/pi-linkup"' ${piModelsModule}
    ! grep -F '"packages/pi-web-access"' ${piModelsModule}
    grep -F '"packages/pi-subagents"' ${piModelsModule}
    grep -F '"packages/pi-subagents-tintinweb"' ${piModelsModule}
    grep -F '"packages/pi-continue"' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/settings.json";' ${piModelsModule}

    touch "$out"
  ''
