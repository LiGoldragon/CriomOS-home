{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  ownedAgentModule = { ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; };
  pi = inputs.self.packages.${system}.pi;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-linkup = inputs.self.packages.${system}.pi-linkup;
  pi-subagents = inputs.self.packages.${system}.pi-subagents;
  agent-intercom = inputs.self.packages.${system}.agent-intercom;
  pi-ultra-subagents = inputs.self.packages.${system}.pi-ultra-subagents;
  pi-continue = inputs.self.packages.${system}.pi-continue;
  piLinkupPackage = ../../packages/pi-linkup/default.nix;
  piSubagentsPackage = ../../packages/pi-subagents/default.nix;
  agentIntercomPackage = ../../packages/agent-intercom/default.nix;
  piUltraSubagentsPackage = ../../packages/pi-ultra-subagents/default.nix;
  piContinuePackage = ../../packages/pi-continue/default.nix;
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
  flakeFile = ../../flake.nix;
  piRuntimeHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs ownedAgentPackages;
      hexis = inputs.hexis.packages.${system}.default;
      horizon = {
        node = {
          typeIs.largeAiRouter = false;
          behavesAs.largeAi = true;
          criomeDomainName = "pi-runtime-test.invalid";
          services = [ ];
        };
        exNodes = { };
        users.pi-runtime-test = {
          name = "pi-runtime-test";
          size.min = true;
        };
      };
      user.size.min = true;
    };
    modules = [
      ../../modules/home/core-packages.nix
      piModelsModule
      ownedAgentModule
      ../../modules/home/profiles/min/agent-intercom.nix
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
  runtimeAgentIntercom = pkgs.lib.removeSuffix "/share/agent-intercom/pi" (
    toString piRuntimeFiles.".pi/agent/packages/agent-intercom-pi".source
  );
  primaryGenerated = inputs.primary-generated-src;
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
    jq -e '.name == "pi-subagents" and .version == "0.36.3" and .pi.extensions == ["./index.ts"] and .pi.skills == ["./skills"]' \
      "${pi-subagents}/share/pi-packages/pi-subagents/package.json"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/index.ts"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/schemas.ts"
    test -f "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/tool-description.ts"
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
    agent_intercom_pi="${agent-intercom}/share/agent-intercom/pi"
    test -f "$agent_intercom_pi/index.ts"
    test -f "$agent_intercom_pi/skills/pi-intercom/SKILL.md"
    test -d "$agent_intercom_pi/node_modules/tsx"
    test -d "$agent_intercom_pi/node_modules/typebox"
    test -d "$agent_intercom_pi/node_modules/esbuild"
    test -d "$agent_intercom_pi/node_modules/get-tsconfig"
    test -d "$agent_intercom_pi/node_modules/resolve-pkg-maps"
    test -d "$agent_intercom_pi/node_modules/@dataforxyz/agent-intercom-core/dist"
    test -x "$agent_intercom_pi/node_modules/@esbuild/linux-x64/bin/esbuild"
    ${pkgs.nodejs}/bin/node "$agent_intercom_pi/node_modules/tsx/dist/cli.mjs" --version >/dev/null

    intercom_home="$TMPDIR/intercom-home"
    broker_socket="$intercom_home/.pi/agent/intercom/broker.sock"
    HOME="$intercom_home" ${pkgs.nodejs}/bin/node \
      "$agent_intercom_pi/node_modules/tsx/dist/cli.mjs" \
      "$agent_intercom_pi/broker/broker.ts" \
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

    jq -e '.name == "@dataforxyz/agent-intercom-pi" and .version == "0.10.0" and .pi.extensions == ["./index.ts"] and .pi.skills == ["./skills"]' \
      "$agent_intercom_pi/package.json"
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
    jq -e '.version == "0.1.3" and .pi.extensions == ["./extensions/live-theme-control.ts"] and .pi.skills == ["./skills"]' \
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
    ! grep -q -F 'setStatus(' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'PI_LIVE_THEME_CONTROL_STATUS' \
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
    grep -F 'inputs.agent-intercom-pi-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-codex-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-claude-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-opencode-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-orchestrator-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-core-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-tsx-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-typebox-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-esbuild-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-esbuild-linux-x64-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-get-tsconfig-src' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-resolve-pkg-maps-src' ${agentIntercomPackage}
    grep -F 'inputs.pi-ultra-subagents-src' ${piUltraSubagentsPackage}
    grep -F 'inputs.pi-ultra-subagents-typebox-src' ${piUltraSubagentsPackage}
    grep -F 'inputs.pi-continue-src' ${piContinuePackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piLinkupPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${piSubagentsPackage}
    ! grep -E '\bfetchurl\b|hash[[:space:]]*=' ${agentIntercomPackage}
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
    printf '%s\n' \
      '{"openai-codex":{"type":"oauth","access":"test-only-no-network","refresh":"test-only-no-network","expires":4102444800000}}' \
      > "$normalPiHome/.pi/agent/auth.json"
    (
      cd "$normalPiHome/workspace"
      HOME="$normalPiHome" PI_OFFLINE=1 \
        PI_PACKAGE_DIR="${pi}/lib/pi-monorepo/packages/coding-agent" \
        PATH="${pi}/bin:$PATH" pi --list-models gpt-5.6
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
    link_runtime_file "$runtimeHome/.pi/agent/extensions/subagent/config.json" \
      "${piRuntimeFiles.".pi/agent/extensions/subagent/config.json".source}"
    link_runtime_file "$runtimeHome/.pi/agent/packages/agent-intercom-pi" \
      "${piRuntimeFiles.".pi/agent/packages/agent-intercom-pi".source}"
    link_runtime_file "$runtimeHome/.pi/agent/packages/agent-intercom-orchestrator" \
      "${piRuntimeFiles.".pi/agent/packages/agent-intercom-orchestrator".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/SYSTEM.md" \
      "${piRuntimeFiles.".pi-testing/agent/SYSTEM.md".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/packages/pi-subagents" \
      "${piRuntimeFiles.".pi-testing/agent/packages/pi-subagents".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/extensions/subagent/config.json" \
      "${piRuntimeFiles.".pi-testing/agent/extensions/subagent/config.json".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/packages/agent-intercom-pi" \
      "${piRuntimeFiles.".pi-testing/agent/packages/agent-intercom-pi".source}"
    link_runtime_file "$runtimeHome/.pi-testing/agent/packages/agent-intercom-orchestrator" \
      "${piRuntimeFiles.".pi-testing/agent/packages/agent-intercom-orchestrator".source}"
    mkdir -p "$runtimeHome/.codex" "$runtimeHome/.config/opencode"
    DRY_RUN_CMD=
    run() { "$@"; }
    export HOME="$runtimeHome"
    ${piRuntimeActivations.mergePiSettings.data}
    ${piRuntimeActivations.mergePiIntercomConfig.data}
    ${piRuntimeActivations.mergePiTestingSettings.data}
    ${piRuntimeActivations.mergePiTestingIntercomConfig.data}
    ${piRuntimeActivations.mergeAgentIntercomCodexMcp.data}
    ${piRuntimeActivations.mergeAgentIntercomClaudeMcp.data}
    ${piRuntimeActivations.mergeAgentIntercomOpenCodeServerPlugin.data}
    ${piRuntimeActivations.mergeAgentIntercomOpenCodeTuiPlugin.data}

    test ! -e "$runtimeHome/.pi/agents"
    test -L "$runtimeHome/.pi/agent/packages/agent-intercom-pi"
    test -L "$runtimeHome/.pi/agent/packages/agent-intercom-orchestrator"
    test -L "$runtimeHome/.pi-testing/agent/packages/agent-intercom-pi"
    test -L "$runtimeHome/.pi-testing/agent/packages/agent-intercom-orchestrator"
    jq -e '.enabled == true and .inboundTrigger == "always" and (.brokerArgs[0] | endswith("agent-intercom/pi/node_modules/tsx/dist/cli.mjs"))' \
      "$runtimeHome/.pi/agent/intercom/config.json"
    jq -e '.enabled == true and .inboundTrigger == "always"' \
      "$runtimeHome/.pi-testing/agent/intercom/config.json"
    grep -F '${runtimeAgentIntercom}/bin/codex-intercom-mcp' "$runtimeHome/.codex/config.toml"
    jq -e '.mcpServers."agent-intercom".command == "${runtimeAgentIntercom}/bin/claude-intercom-mcp"' \
      "$runtimeHome/.claude.json"
    jq -e '.plugin == ["${runtimeAgentIntercom}/share/agent-intercom/opencode/dist/plugin.mjs"]' \
      "$runtimeHome/.config/opencode/opencode.json"
    jq -e '.plugin == ["${runtimeAgentIntercom}/share/agent-intercom/opencode/dist/tui.mjs"]' \
      "$runtimeHome/.config/opencode/tui.json"

    cat > "$TMPDIR/check-managed-project-roles.ts" <<'EOF'
    import * as fs from "node:fs";
    import { discoverAgents } from "${pi-subagents}/share/pi-packages/pi-subagents/src/agents/agents.ts";
    import {
      COMPACT_SUBAGENT_TOOL_DESCRIPTION,
      FULL_SUBAGENT_TOOL_DESCRIPTION,
    } from "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/tool-description.ts";
    import { FullSubagentParams, SubagentParams } from "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/schemas.ts";

    const projectRoot = process.argv[2];
    if (!projectRoot) throw new Error("expected generated project root");

    const expected: Record<string, [string, string | false]> = {
      "read-trivial": ["openai-codex/gpt-5.4-mini", "medium"],
      "read-ordinary": ["openai-codex/gpt-5.6-luna", "high"],
      "read-demanding": ["openai-codex/gpt-5.6-terra", "high"],
      "read-critical": ["openai-codex/gpt-5.6-terra", "xhigh"],
      "write-trivial": ["openai-codex/gpt-5.4-mini", "medium"],
      "write-ordinary": ["openai-codex/gpt-5.6-luna", "high"],
      "write-demanding": ["openai-codex/gpt-5.6-terra", "high"],
      "write-critical": ["openai-codex/gpt-5.6-terra", "xhigh"],
    };

    const agents = discoverAgents(projectRoot, "project").agents.filter((agent) => agent.source === "project");
    if (agents.length !== Object.keys(expected).length) throw new Error(`expected eight generated read/write roles, got ''${agents.length}`);
    for (const agent of agents) {
      const contract = expected[agent.name];
      if (!contract) throw new Error(`undeclared generated role: ''${agent.name}`);
      const [model, thinking] = contract;
      if (agent.source !== "project" || agent.model !== model || agent.thinking !== thinking) {
        throw new Error(`effective model metadata mismatch for ''${agent.name}`);
      }
    }

    const retiredRoles = ["manager", "generalist", "intent-recorder", "intent-curator", "intent-translator"];
    if (agents.some((agent) => retiredRoles.includes(agent.name))) throw new Error("retired generated role remains discoverable");
    if (agents.some((agent) => /claude|fable/i.test(agent.model ?? ""))) throw new Error("generated roster contains a forbidden Claude Fable model");
    if (fs.existsSync("${pi-subagents}/share/pi-packages/pi-subagents/src/agents/project-role-policy.ts")) {
      throw new Error("removed project-role authorization module is still packaged");
    }
    if (agents.some((agent) => "projectRole" in agent)) {
      throw new Error("generated role metadata must remain inert frontmatter, not runtime state");
    }

    const briefAuthority = "The brief is your authority. Decide what it settles; return what it does not.";
    const readOnlyBoundary = "Do not edit files, commit, or push. Fetching, cloning, and tool queries are fine.";
    const approvalGate = "Do not make material authority, security, compatibility, schema, curriculum, or deployment changes without explicit psyche approval.";
    for (const agent of agents) {
      const packet = fs.readFileSync(projectRoot + "/.pi/agents/" + agent.name + ".md", "utf8");
      if (packet.split(briefAuthority).length - 1 !== 1) {
        throw new Error(`generated Pi packet lacks exactly one brief-authority clause: ''${agent.name}`);
      }
      if (!packet.includes(approvalGate)) {
        throw new Error(`generated Pi packet lacks the material-change approval gate: ''${agent.name}`);
      }
      if (packet.includes(readOnlyBoundary) !== agent.name.startsWith("read-")) {
        throw new Error(`generated Pi packet has the wrong read-only boundary: ''${agent.name}`);
      }
    }

    const psycheInteraction = fs.readFileSync(projectRoot + "/.agents/skills/psyche-interraction/SKILL.md", "utf8");
    const intentLog = fs.readFileSync(projectRoot + "/.agents/skills/intent-log/SKILL.md", "utf8");
    const workspaceDoctrine = fs.readFileSync(projectRoot + "/AGENTS.md", "utf8");
    const exactSpiritApproval = "Before a core Spirit capture or mutation, show the psyche the exact proposed record wording and scope, then receive explicit approval.";
    const approvedRecordScope = "Before capture or mutation, use only psyche-approved record wording and scope.";
    const noInventedMetadata = "Do not synthesize confidence, access-boundary, or named-particular metadata.";
    const separateConfidentiality = "Route content requiring confidentiality to a separate higher-layer Spirit component in its own environment.";
    if (!psycheInteraction.includes(exactSpiritApproval)) {
      throw new Error("generated psyche-interaction skill lacks exact Spirit wording-and-scope approval");
    }
    if (!intentLog.includes(approvedRecordScope) || !intentLog.includes(noInventedMetadata) || !intentLog.includes(separateConfidentiality)) {
      throw new Error("generated Spirit recording skill lacks the approved record-shape doctrine");
    }
    if (!workspaceDoctrine.includes("confidentiality belongs to a separate higher-layer Spirit component in its own") ||
        !workspaceDoctrine.includes("core Spirit records, commits, and chat.")) {
      throw new Error("workspace boot doctrine does not keep confidentiality above core Spirit");
    }
    if (workspaceDoctrine.includes("public Spirit records") || intentLog.includes("proposed privacy")) {
      throw new Error("retired core Spirit privacy doctrine remains in the generated workspace");
    }

    const compactSurfaceSize = COMPACT_SUBAGENT_TOOL_DESCRIPTION.length + JSON.stringify(SubagentParams).length;
    if (COMPACT_SUBAGENT_TOOL_DESCRIPTION.length >= FULL_SUBAGENT_TOOL_DESCRIPTION.length * 0.8) {
      throw new Error(`compact tool description is not materially smaller: ''${compactSurfaceSize}`);
    }
    if (!COMPACT_SUBAGENT_TOOL_DESCRIPTION.includes("DIRECT LAUNCH:")) {
      throw new Error("compact description omitted direct-launch guidance");
    }
    const minimalProperties = (SubagentParams as { properties: Record<string, unknown> }).properties;
    if (Object.keys(minimalProperties).sort().join(",") !== "action,agent,async,context,task") {
      throw new Error("compact schema does not expose only direct-launch recovery fields");
    }
    const fullProperties = (FullSubagentParams as { properties: Record<string, unknown> }).properties;
    for (const mechanism of ["agent", "task", "action", "chain", "tasks", "acceptance", "turnBudget", "worktree"]) {
      if (!(mechanism in fullProperties)) throw new Error(`full schema mechanism missing: ''${mechanism}`);
    }
    if (!FULL_SUBAGENT_TOOL_DESCRIPTION.includes("DIAGNOSTICS:") || !FULL_SUBAGENT_TOOL_DESCRIPTION.includes("CHAIN:")) {
      throw new Error("full optional mechanism description is incomplete");
    }

    console.log(`managed-role-witness roles=''${agents.length} compact-surface=''${compactSurfaceSize} role-metadata=inert spirit-doctrine=current`);
    EOF

    check_effective_pi_layout() {
      agent_directory="$1"
      test -f "$agent_directory/settings.json"
      ${pkgs.jq}/bin/jq -e '.subagents.disableBuiltins == true' "$agent_directory/settings.json"
      test -L "$agent_directory/packages/pi-subagents"
      test -f "$agent_directory/SYSTEM.md"
      ${pkgs.jq}/bin/jq -e '
        .toolDescriptionMode == "compact" and
        .asyncByDefault == true and
        .proactiveSkillSubagents == false and
        (has("projectRolePolicy") | not)
      ' "$agent_directory/extensions/subagent/config.json"
    }

    check_effective_pi_layout "$runtimeHome/.pi/agent"
    check_effective_pi_layout "$runtimeHome/.pi-testing/agent"

    HOME="$runtimeHome" ${pkgs.nodejs}/bin/node \
      "${pi-subagents}/share/pi-packages/pi-subagents/node_modules/jiti/lib/jiti-cli.mjs" \
      "$TMPDIR/check-managed-project-roles.ts" "${primaryGenerated}"

    ${pkgs.jq}/bin/jq -e '
      .nodes.skills.locked.rev == "0b6ad2f33a78dd515bebe1f5487fd1cdfbbe8f58"
    ' "${primaryGenerated}/flake.lock"

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
    grep -F '"packages/agent-intercom-pi"' ${piModelsModule}
    grep -F '"packages/agent-intercom-orchestrator"' ${piModelsModule}
    ! grep -F '"packages/pi-intercom"' ${piModelsModule}
    ! grep -F '"packages/pi-subagents-tintinweb"' ${piModelsModule}
    ! grep -F '"packages/pi-ultra-subagents"' ${piModelsModule}
    grep -F 'normalPiPackages = [' ${piModelsModule}
    ! grep -F 'piTestingPackages = [' ${piModelsModule}
    grep -F 'packages = normalPiPackages;' ${piModelsModule}
    grep -F 'piTestingSettingsConfig = piSettingsConfig;' ${piModelsModule}
    grep -F 'github:LiGoldragon/pi-subagents-nicobailon/8b7d204fd0fd4427acdea5c1c60a2697221194ea' ${flakeFile}
    grep -F 'github:LiGoldragon/primary/62eac67630c020caa8c154f7dc6ebba6196cf5d2' ${flakeFile}
    grep -F 'if (toolDescriptionMode !== "compact") {' "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/index.ts"
    grep -F 'registerWaitTool(pi, state, waitToolConfig.enabled);' "${pi-subagents}/share/pi-packages/pi-subagents/src/extension/index.ts"
    ! test -e "${pi-subagents}/share/pi-packages/pi-subagents/src/agents/project-role-policy.ts"
    ! grep -R -E 'authorizeProjectRoleDispatch|projectRoleDispatchKind|PROJECT_ROLE_METADATA_ENV|projectRolePolicy' "${pi-subagents}/share/pi-packages/pi-subagents/src"
    grep -F 'github:dataforxyz/agent-intercom-pi/b6f8f9d08c8c5ec7141a0258ce61cda59d327a20' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-codex/ea1c5b538c95b89af3fd36344396779e2eadbadb' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-claude/d62b3c85547b8b83fdfe06afb38968646fe813b8' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-opencode/9d81100ea074f68f6466656c65536504209eb060' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-orchestrator/a7e16bd4386726002ab6880b35ebacdeef00fd0d' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-core/8316cbab548f422ad11c78ed887fabeef94817c1' ${flakeFile}
    ! grep -F 'github:LiGoldragon/pi-intercom' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${flakeFile}
    ! grep -F 'pi-subagents-tintinweb-testing-src' ${piModelsModule}
    ! grep -F 'pi-subagents-tintinweb-testing' ${piModelsModule}
    grep -F 'home.file.".pi/agent/packages/pi-subagents".source' ${piModelsModule}
    grep -F 'home.file.".pi-testing/agent/packages/pi-subagents".source' ${piModelsModule}
    test "$(grep -F '"''${pi-subagents}/share/pi-packages/pi-subagents";' ${piModelsModule} | wc -l)" -eq 2
    grep -F 'agentIntercomCore' ${agentIntercomPackage}
    grep -F 'piIntercomConfig = {' ${piModelsModule}
    grep -F 'brokerCommand = "''${pkgs.nodejs}/bin/node";' ${piModelsModule}
    grep -F 'agent-intercom/pi/node_modules/tsx/dist/cli.mjs' ${piModelsModule}
    grep -F 'home.sessionVariables.PI_INTERCOM_EXTENSION_DIR = "''${agent-intercom}/share/agent-intercom/pi";' ${piModelsModule}
    test -x ${agent-intercom}/bin/coi
    ! test -e ${agent-intercom}/bin/codex
    ! test -e ${agent-intercom}/bin/codex-raw
    test -x ${agent-intercom}/bin/cci
    ! test -e ${agent-intercom}/bin/claude
    test -x ${agent-intercom}/bin/claude-raw
    ! grep -F ${agent-intercom}/bin/codex ${agent-intercom}/bin/coi
    grep -F -- '--dangerously-skip-permissions' ${agent-intercom}/bin/cci
    ! grep -F ${agent-intercom}/bin/claude ${agent-intercom}/bin/cci
    test -x ${agent-intercom}/bin/codex-intercom-mcp
    test -x ${agent-intercom}/bin/claude-intercom-mcp
    ! test -e ${agent-intercom}/bin/agent-intercom-access
    test -f ${agent-intercom}/share/agent-intercom/opencode/dist/plugin.mjs
    test -f ${agent-intercom}/share/agent-intercom/opencode/dist/tui.mjs
    grep -F 'file = "$HOME/.pi/agent/intercom/config.json";' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/intercom/config.json";' ${piModelsModule}
    ! grep -F 'home.file.".pi-testing/agent/packages/pi-ultra-subagents".source' ${piModelsModule}
    ! grep -F 'home.file.".pi/agent/packages/pi-subagents-tintinweb".source' ${piModelsModule}
    grep -F '"packages/pi-continue"' ${piModelsModule}
    ! grep -F '"packages/pi-intercom"' ${piModelsModule}
    grep -F 'file = "$HOME/.pi-testing/agent/settings.json";' ${piModelsModule}

    touch "$out"
  ''
