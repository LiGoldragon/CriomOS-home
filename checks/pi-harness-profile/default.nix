{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-linkup = inputs.self.packages.${system}.pi-linkup;
  pi-subagents = inputs.self.packages.${system}.pi-subagents;
  pi-intercom = inputs.self.packages.${system}.pi-intercom;
  pi-ultra-subagents = inputs.self.packages.${system}.pi-ultra-subagents;
  pi-continue = inputs.self.packages.${system}.pi-continue;
  piLinkupPackage = ../../packages/pi-linkup/default.nix;
  piSubagentsPackage = ../../packages/pi-subagents/default.nix;
  piIntercomPackage = ../../packages/pi-intercom/default.nix;
  piUltraSubagentsPackage = ../../packages/pi-ultra-subagents/default.nix;
  piContinuePackage = ../../packages/pi-continue/default.nix;
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
  flakeFile = ../../flake.nix;
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
    grep -F 'Subagents are independent Pi processes.' "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    grep -F 'selected child agent, runtime, packages, and prompt, not from the parent' "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    ! grep -F 'Chains default to clarify mode' "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    test -f "${pi-intercom}/share/pi-packages/pi-intercom/index.ts"
    test -f "${pi-intercom}/share/pi-packages/pi-intercom/skills/pi-intercom/SKILL.md"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/tsx"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/typebox"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/esbuild"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/get-tsconfig"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/resolve-pkg-maps"
    test -x "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/@esbuild/linux-x64/bin/esbuild"
    jq -e '.name == "pi-intercom" and .version == "0.6.0" and .pi.extensions == ["./index.ts"] and .pi.skills == ["./skills"]' \
      "${pi-intercom}/share/pi-packages/pi-intercom/package.json"
    test -f "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/extensions/subagent/index.ts"
    test -f "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/extensions/subagent/agents.ts"
    test -d "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/node_modules/typebox"
    test -f "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/agents/planner.md"
    test -f "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/agents/worker.md"
    jq -e '.name == "pi-ultra-subagents" and .version == "0.1.0" and .pi.extensions == ["./extensions/subagent"]' \
      "${pi-ultra-subagents}/share/pi-packages/pi-ultra-subagents/package.json"
    test -f "${pi-continue}/share/pi-packages/pi-continue/extensions/continue/index.ts"
    test -f "${pi-continue}/share/pi-packages/pi-continue/assets/user/continuation_base.md"

    test -f "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-dark.json"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-light.json"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/skills/gws/SKILL.md"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/skills/pi-internals/SKILL.md"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/operator-safety.ts"
    jq -e '.version == "0.1.2" and .pi.extensions == ["./extensions/live-theme-control.ts"] and .pi.skills == ["./skills"]' \
      "${pi-criomos}/share/pi-packages/pi-criomos/package.json"
    grep -F "You are Pi, a coding agent running inside the user's terminal." \
      "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md"
    grep -F 'The concrete tool schemas, availability, and permission rules are authoritative.' \
      "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md"
    grep -F 'ctx.ui.getTheme(selection.themeName)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -F 'ctx.ui.setTheme(themeInstance)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -F 'ctx.ui.setTheme(selection.themeName)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -E 'current-mode|theme-switcher|setTimeout|setInterval|watchFile|fs\.watch' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -F 'PI_LIVE_THEME_CONTROL_REGISTRY_DIRECTORY' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -F 'randomUUID' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -F 'registryEntryExtension = ".path"' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'useActiveContext' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'containExternalCallback' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'staleContextMessageFragment = "This extension ctx is stale after session replacement or reload"' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'retireAfterStaleContext' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'removeOwnedFilesSynchronously' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'LiveThemeControlProcessCleanup.register' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'containedError.isStaleSession()' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'logContainedError' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -E 'notify\([^)]*(stale|ctx|contained)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -E 'setStatus\([^)]*(stale|ctx|contained)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'this.ctx.ui.' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'theme socket registered' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -F 'pi-live-theme.sock' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    jq -e '.name == "criomos-dark" and (.colors | length == 51)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-dark.json"
    jq -e '.name == "criomos-light" and (.colors | length == 51)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/themes/criomos-light.json"

    grep -F 'inputs.pi-linkup-src' ${piLinkupPackage}
    grep -F 'inputs.pi-utils-ui-src' ${piLinkupPackage}
    grep -F 'inputs.pi-subagents-src' ${piSubagentsPackage}
    grep -F 'inputs.pi-intercom-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-tsx-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-typebox-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-esbuild-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-esbuild-linux-x64-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-get-tsconfig-src' ${piIntercomPackage}
    grep -F 'inputs.pi-intercom-resolve-pkg-maps-src' ${piIntercomPackage}
    grep -F 'inputs.pi-ultra-subagents-src' ${piUltraSubagentsPackage}
    grep -F 'inputs.pi-ultra-subagents-typebox-src' ${piUltraSubagentsPackage}
    grep -F 'inputs.pi-continue-src' ${piContinuePackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piLinkupPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piSubagentsPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piIntercomPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piUltraSubagentsPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piContinuePackage}

    grep -F 'defaultProvider = "openai-codex";' ${piModelsModule}
    grep -F 'defaultOpenAiCodexModel = "gpt-5.5";' ${piModelsModule}
    grep -F 'defaultModel = defaultOpenAiCodexModel;' ${piModelsModule}
    grep -F 'defaultThinkingLevel = "high";' ${piModelsModule}
    grep -F '"openai-codex/gpt-5.4-mini"' ${piModelsModule}
    grep -F 'localLlmApiKeyCommand = "!gopass show -o goldragon.criome/local-llm-api-token";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi/agent/auth.json";' ${piModelsModule}
    grep -F 'theme = "criomos-light/criomos-dark";' ${piModelsModule}
    grep -F 'doubleEscapeAction = "tree";' ${piModelsModule}
    grep -F 'enabled = true;' ${piModelsModule}
    grep -F 'reserveTokens = 32768;' ${piModelsModule}
    grep -F 'keepRecentTokens = 20000;' ${piModelsModule}
    grep -F '"/compaction" = "always";' ${piModelsModule}
    grep -F 'source = "packages/pi-criomos";' ${piModelsModule}
    grep -F 'extensions = [ "extensions/live-theme-control.ts" ];' ${piModelsModule}
    grep -F 'home.activation.preparePiPackageSymlink = lib.hm.dag.entryBefore [ "checkLinkTargets" ]' ${piModelsModule}
    grep -F '.name == "@earendil-works/pi-coding-agent"' ${piModelsModule}
    grep -F 'criomos/pi-package-migrations' ${piModelsModule}
    grep -F 'home.file.".pi/agent/SYSTEM.md".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/SYSTEM.md".source' ${piModelsModule}
    grep -F 'system/SYSTEM.md' ${piModelsModule}
    grep -F '"packages/pi-linkup"' ${piModelsModule}
    ! grep -F '"packages/pi-web-access"' ${piModelsModule}
    grep -F '"packages/pi-subagents"' ${piModelsModule}
    grep -F '"packages/pi-intercom"' ${piModelsModule}
    ! grep -F '"packages/pi-subagents-tintinweb"' ${piModelsModule}
    ! grep -F '"packages/pi-ultra-subagents"' ${piModelsModule}
    grep -F 'normalPiPackages = [' ${piModelsModule}
    ! grep -F 'piTestingPackages = [' ${piModelsModule}
    grep -F 'packages = normalPiPackages;' ${piModelsModule}
    grep -F 'piTestingSettingsConfig = piSettingsConfig;' ${piModelsModule}
    grep -F 'github:LiGoldragon/pi-subagents/49697bccba12aaa50ac90f2dd54fbe71d4fd0265' ${flakeFile}
    grep -F 'https://registry.npmjs.org/pi-intercom/-/pi-intercom-0.6.0.tgz' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${piModelsModule}
    ! grep -F 'pi-subagents-tintinweb-testing' ${piModelsModule}
    grep -F 'home.file.".pi/agent/packages/pi-subagents".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-subagents".source' ${piModelsModule}
    test "$(grep -F '"''${pi-subagents}/share/pi-packages/pi-subagents";' ${piModelsModule} | wc -l)" -eq 2
    grep -F 'home.file.".pi/agent/packages/pi-intercom".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-intercom".source' ${piModelsModule}
    test "$(grep -F '"''${pi-intercom}/share/pi-packages/pi-intercom";' ${piModelsModule} | wc -l)" -eq 2
    grep -F 'piIntercomConfig = {' ${piModelsModule}
    grep -F 'file = "$HOME/.pi/agent/intercom/config.json";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/intercom/config.json";' ${piModelsModule}
    ! grep -F 'home.file.".pi-testing/agent/packages/pi-ultra-subagents".source' ${piModelsModule}
    ! grep -F 'home.file.".pi/agent/packages/pi-subagents-tintinweb".source' ${piModelsModule}
    grep -F '"packages/pi-continue"' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/settings.json";' ${piModelsModule}

    touch "$out"
  ''
