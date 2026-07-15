{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi = inputs.self.packages.${system}.pi;
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
  piRuntimeHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hexis = inputs.hexis.packages.${system}.default;
      horizon = {
        node = {
          typeIs.largeAiRouter = false;
          behavesAs.largeAi = true;
          criomeDomainName = "pi-runtime-test.invalid";
        };
        exNodes = { };
      };
      user.size.min = true;
    };
    modules = [
      piModelsModule
      {
        home = {
          username = "pi-runtime-test";
          homeDirectory = "/home/pi-runtime-test";
          stateVersion = "26.05";
        };
      }
    ];
  };
  piRuntimeFiles = piRuntimeHome.config.home.file;
  piRuntimeActivations = piRuntimeHome.config.home.activation;
in
pkgs.runCommand "pi-harness-profile"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gnugrep
      pkgs.nodejs
      pkgs.util-linux
    ];
  }
  ''
    set -eu

    test -f "${pi-linkup}/share/pi-packages/pi-linkup/package.json"
    test -d "${pi-linkup}/share/pi-packages/pi-linkup/node_modules/@aliou/pi-utils-ui"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/index.ts"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/skills/pi-subagents/SKILL.md"
    jq -e '.name == "pi-subagents" and .version == "0.35.0" and .pi.extensions == ["./src/extension/index.ts"]' \
      "${pi-subagents}/share/pi-packages/pi-subagents/package.json"
    grep -F 'export function buildSubagentParams(mode: ToolDescriptionMode | undefined = "compact")' \
      "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/schemas.ts"
    grep -F 'return value === "full" || value === "compact" || value === "custom";' \
      "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/tool-description.ts"
    grep -F 'if (mode === undefined) return "compact";' \
      "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/tool-description.ts"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/typebox/package.json"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/@earendil-works/pi-tui/package.json"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/src/runs/background/async-execution.ts"
    grep -F 'runner.stderr.log' "${pi-subagents}/share/pi-packages/pi-subagents/src/runs/background/async-execution.ts"
    # The stable reconciliation contract is a durable repaired-stale event,
    # not a particular explanatory sentence in its human-facing message.
    grep -F 'type: "subagent.run.repaired_stale"' \
      "${pi-subagents}/share/pi-packages/pi-subagents/src/runs/background/stale-run-reconciler.ts"
    grep -F 'result: "passed" | "failed" | "blocked" | "not-run";' \
      "${pi-subagents}/share/pi-packages/pi-subagents/src/shared/types.ts"
    test -f "${pi-intercom}/share/pi-packages/pi-intercom/index.ts"
    test -f "${pi-intercom}/share/pi-packages/pi-intercom/skills/pi-intercom/SKILL.md"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/tsx"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/typebox"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/esbuild"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/get-tsconfig"
    test -d "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/resolve-pkg-maps"
    test -x "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/@esbuild/linux-x64/bin/esbuild"
    ${pkgs.nodejs}/bin/node "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/tsx/dist/cli.mjs" --version >/dev/null

    intercom_home="$TMPDIR/intercom-home"
    broker_socket="$intercom_home/.pi/agent/intercom/broker.sock"
    HOME="$intercom_home" ${pkgs.nodejs}/bin/node \
      "${pi-intercom}/share/pi-packages/pi-intercom/node_modules/tsx/dist/cli.mjs" \
      "${pi-intercom}/share/pi-packages/pi-intercom/broker/broker.ts" \
      >"$TMPDIR/intercom-broker.log" 2>&1 &
    broker_pid=$!
    trap 'kill "$broker_pid" 2>/dev/null || true; wait "$broker_pid" 2>/dev/null || true' EXIT
    for attempt in $(seq 1 50); do
      test -S "$broker_socket" && break
      sleep 0.1
    done
    test -S "$broker_socket"
    kill "$broker_pid"
    wait "$broker_pid" || true
    trap - EXIT

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
    grep -F 'ctx.setTheme(selection.themeName)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -F 'setTheme(theme: string): void;' \
      "${pi}/lib/pi-monorepo/packages/coding-agent/src/core/extensions/types.ts"
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
    grep -F 'src = inputs.pi-subagents-src;' ${piSubagentsPackage}
    grep -F 'npmDepsHash' ${piSubagentsPackage}
    ! grep -F '.patch' ${piSubagentsPackage}
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
    grep -F 'defaultOpenAiCodexModel = "gpt-5.6-sol";' ${piModelsModule}
    grep -F 'defaultModel = defaultOpenAiCodexModel;' ${piModelsModule}
    grep -F 'defaultThinkingLevel = "high";' ${piModelsModule}
    grep -F '"openai-codex/gpt-5.6-sol"' ${piModelsModule}
    grep -F '"openai-codex/gpt-5.6-terra"' ${piModelsModule}
    grep -F '"openai-codex/gpt-5.6-luna"' ${piModelsModule}
    ! grep -F '"openai-codex/gpt-5.5"' ${piModelsModule}

    # Launch the packaged `pi` without PI_CODING_AGENT_DIR or model flags;
    # the temporary HOME preserves the standard $HOME/.pi/agent lookup.
    normalPiHome="$TMPDIR/normal-pi-home"
    mkdir -p "$normalPiHome/.pi/agent" "$normalPiHome/workspace"
    printf '%s\n' \
      '{' \
      '  "defaultProvider": "openai-codex",' \
      '  "defaultModel": "gpt-5.6-sol",' \
      '  "defaultThinkingLevel": "high",' \
      '  "enabledModels": [' \
      '    "openai-codex/gpt-5.6-sol",' \
      '    "openai-codex/gpt-5.6-terra",' \
      '    "openai-codex/gpt-5.6-luna"' \
      '  ]' \
      '}' > "$normalPiHome/.pi/agent/settings.json"
    printf '%s\n' '{"openai-codex":{"type":"api_key","key":"test-only-no-network"}}' \
      > "$normalPiHome/.pi/agent/auth.json"
    (
      cd "$normalPiHome/workspace"
      HOME="$normalPiHome" PI_OFFLINE=1 PATH="${pi}/bin:$PATH" \
        pi --list-models gpt-5.6
    ) > "$normalPiHome/launcher.log"
    grep -F 'gpt-5.6-sol' "$normalPiHome/launcher.log"
    grep -F 'gpt-5.6-terra' "$normalPiHome/launcher.log"
    grep -F 'gpt-5.6-luna' "$normalPiHome/launcher.log"
    ! grep -F 'gpt-5.5' "$normalPiHome/launcher.log"

    # Materialize the owning Home Manager module's evaluated file layout into
    # an isolated HOME, then run its managed settings activations. The resulting
    # normal and testing directories are passed to Pi and pi-subagents at runtime;
    # this guards effective layout and discovery rather than only matching Nix text.
    runtimeHome="$TMPDIR/pi-runtime-home"
    link_runtime_file() {
      target="$1"
      source="$2"
      mkdir -p "$(dirname "$target")"
      ln -s "$source" "$target"
    }
    link_runtime_file "$runtimeHome/.local/share/criomos/pi/package" \
      "${piRuntimeFiles.".local/share/criomos/pi/package".source}"
    link_runtime_file "$runtimeHome/.pi/agent/SYSTEM.md" \
      "${piRuntimeFiles.".pi/agent/SYSTEM.md".source}"
    link_runtime_file "$runtimeHome/.pi/agent/packages/pi-subagents" \
      "${piRuntimeFiles.".pi/agent/packages/pi-subagents".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/SYSTEM.md" \
      "${piRuntimeFiles.".pi-testing/agent/SYSTEM.md".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/packages/pi-subagents" \
      "${piRuntimeFiles.".pi-testing/agent/packages/pi-subagents".source}"
    DRY_RUN_CMD=
    run() { "$@"; }
    export HOME="$runtimeHome"
    ${piRuntimeActivations.mergePiSettings.data}
    ${piRuntimeActivations.mergePiTestingSettings.data}

    test ! -e "$runtimeHome/.pi/agents"

    cat > "$TMPDIR/check-pi-runtime-discovery.ts" <<'EOF'
    import { discoverAgents, discoverAgentsAll } from "${pi-subagents}/share/pi-packages/pi-subagents/src/agents/agents.ts";

    const [cwd, expectedBuiltinState] = process.argv.slice(2);
    if (!cwd || !expectedBuiltinState) throw new Error("expected cwd and builtin state");

    const discovered = discoverAgents(cwd, "both").agents;
    const all = discoverAgentsAll(cwd);
    const builtinVisible = discovered.some((agent) => agent.source === "builtin");
    const projectAgentVisible = discovered.some((agent) => agent.name === "project-runtime-agent" && agent.source === "project");
    const builtinDisabled = all.builtin.every((agent) => agent.disabled === true);

    if (!projectAgentVisible) throw new Error("project-scoped .pi/agents entry was not discovered");
    if (expectedBuiltinState === "project-enabled") {
      if (!builtinVisible || builtinDisabled) throw new Error("project settings did not override user builtin suppression");
    } else if (expectedBuiltinState === "user-disabled") {
      if (builtinVisible || !builtinDisabled) throw new Error("user builtin suppression was not applied");
    } else {
      throw new Error(`unknown expected builtin state: ''${expectedBuiltinState}`);
    }
    EOF

    check_effective_pi_layout() {
      agent_directory="$1"
      layout_name="$2"
      project_directory="$runtimeHome/$layout_name-project"

      test -f "$agent_directory/settings.json"
      ${pkgs.jq}/bin/jq -e '.subagents.disableBuiltins == true' "$agent_directory/settings.json"
      test -L "$agent_directory/packages/pi-subagents"
      test -f "$agent_directory/SYSTEM.md"

      mkdir -p "$project_directory/.pi/agents"
      cat > "$project_directory/.pi/agents/project-runtime-agent.md" <<'EOF'
    ---
    name: project-runtime-agent
    description: Hermetic project discovery witness
    ---
    This agent exists only to prove project-scoped discovery.
    EOF
      printf '%s\n' '{"subagents":{"disableBuiltins":false}}' > "$project_directory/.pi/settings.json"

      if [ "$layout_name" = normal ]; then
        (
          cd "$project_directory"
          HOME="$runtimeHome" PI_OFFLINE=1 PATH="${pi}/bin:$PATH" pi list
        ) > "$runtimeHome/$layout_name-pi-list.log"
        (
          cd "$project_directory"
          HOME="$runtimeHome" ${pkgs.nodejs}/bin/node \
            "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs" \
            "$TMPDIR/check-pi-runtime-discovery.ts" "$project_directory" project-enabled
        )
      else
        (
          cd "$project_directory"
          HOME="$runtimeHome" PI_CODING_AGENT_DIR="$agent_directory" PI_OFFLINE=1 PATH="${pi}/bin:$PATH" pi list
        ) > "$runtimeHome/$layout_name-pi-list.log"
        (
          cd "$project_directory"
          HOME="$runtimeHome" PI_CODING_AGENT_DIR="$agent_directory" ${pkgs.nodejs}/bin/node \
            "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs" \
            "$TMPDIR/check-pi-runtime-discovery.ts" "$project_directory" project-enabled
        )
      fi
      grep -F 'pi-subagents' "$runtimeHome/$layout_name-pi-list.log"

      printf '%s\n' '{}' > "$project_directory/.pi/settings.json"
      if [ "$layout_name" = normal ]; then
        (
          cd "$project_directory"
          HOME="$runtimeHome" ${pkgs.nodejs}/bin/node \
            "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs" \
            "$TMPDIR/check-pi-runtime-discovery.ts" "$project_directory" user-disabled
        )
      else
        (
          cd "$project_directory"
          HOME="$runtimeHome" PI_CODING_AGENT_DIR="$agent_directory" ${pkgs.nodejs}/bin/node \
            "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs" \
            "$TMPDIR/check-pi-runtime-discovery.ts" "$project_directory" user-disabled
        )
      fi
    }

    check_effective_pi_layout "$runtimeHome/.pi/agent" normal
    check_effective_pi_layout "$runtimeHome/.pi-testing/agent" testing

    grep -F 'localLlmApiKeyCommand = "!gopass show -o goldragon.criome/local-llm-api-token";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi/agent/auth.json";' ${piModelsModule}
    grep -F 'theme = "criomos-light/criomos-dark";' ${piModelsModule}
    test "$(grep -F '"/theme" = "always";' ${piModelsModule} | wc -l)" -eq 2
    grep -F 'home.file.".pi/agent/packages/pi-criomos".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-criomos".source' ${piModelsModule}
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
    grep -F 'github:LiGoldragon/pi-subagents-nicobailon/31330f7f92a8e0710e71ed109184a539c4e18b33' ${flakeFile}
    grep -F 'github:LiGoldragon/pi-intercom/1fe0fcb210f235890363fbb5c667db4d0896f332' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${piModelsModule}
    ! grep -F 'pi-subagents-tintinweb-testing' ${piModelsModule}
    grep -F 'home.file.".pi/agent/packages/pi-subagents".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-subagents".source' ${piModelsModule}
    test "$(grep -F '"''${pi-subagents}/share/pi-packages/pi-subagents";' ${piModelsModule} | wc -l)" -eq 2
    grep -F 'home.file.".pi/agent/packages/pi-intercom".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-intercom".source' ${piModelsModule}
    test "$(grep -F '"''${pi-intercom}/share/pi-packages/pi-intercom";' ${piModelsModule} | wc -l)" -eq 3
    grep -F 'piIntercomConfig = {' ${piModelsModule}
    grep -F 'brokerCommand = "''${pkgs.nodejs}/bin/node";' ${piModelsModule}
    grep -F 'brokerArgs = [ "''${pi-intercom}/share/pi-packages/pi-intercom/node_modules/tsx/dist/cli.mjs" ];' ${piModelsModule}
    grep -F 'home.sessionVariables.PI_INTERCOM_EXTENSION_DIR = "''${pi-intercom}/share/pi-packages/pi-intercom";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi/agent/intercom/config.json";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/intercom/config.json";' ${piModelsModule}
    ! grep -F 'home.file.".pi-testing/agent/packages/pi-ultra-subagents".source' ${piModelsModule}
    ! grep -F 'home.file.".pi/agent/packages/pi-subagents-tintinweb".source' ${piModelsModule}
    grep -F '"packages/pi-continue"' ${piModelsModule}
    grep -F '"packages/pi-intercom"' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/settings.json";' ${piModelsModule}

    touch "$out"
  ''
