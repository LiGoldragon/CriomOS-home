{ pkgs, inputs, ... }:

let
  minProfileModule = ../../modules/home/profiles/min/default.nix;
  system = pkgs.stdenv.hostPlatform.system;
  claudeCodePackage = inputs.llm-agents.packages.${system}.claude-code;
  codexCliPackage = inputs.codex-cli.packages.${system}.default;
  piPackage = pkgs.callPackage ../../packages/pi { inherit inputs; };
  agentProfilePath = pkgs.symlinkJoin {
    name = "ai-agent-profile-path";
    paths = [
      claudeCodePackage
      codexCliPackage
      piPackage
    ];
  };
in
pkgs.runCommand "ai-agent-launch-orchestration"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.yq-go
    ];
  }
  ''
      set -eu

      ! grep -F 'defaultOrchestrationInstruction =' ${minProfileModule}
      ! grep -F 'Default launch mode: parent orchestrator.' ${minProfileModule}
      ! grep -F 'criomos-default-orchestration-instructions.md' ${minProfileModule}
      ! grep -F 'codex-default-orchestration-developer-instructions.toml-value' ${minProfileModule}
      ! grep -F 'append-system-prompt "$(cat' ${minProfileModule}
      ! grep -F 'developer_instructions=$(cat' ${minProfileModule}
      ! grep -F 'should_inject=1' ${minProfileModule}
      ! grep -F 'CRIOMOS_AGENT_MODE' ${minProfileModule}
      ! grep -F 'PI_SUBAGENT_CHILD' ${minProfileModule}
      ! grep -F 'CLAUDE_CODE_SUBAGENT' ${minProfileModule}
      grep -F 'CLAUDE_CODE_DISABLE_WORKFLOWS = "1";' ${minProfileModule}

      ! grep -F 'claudeCommand = mkDirectAgentCommand "claude"' ${minProfileModule}
      ! grep -F 'codexCommand = mkDirectAgentCommand "codex"' ${minProfileModule}
      ! grep -F 'piCommand = mkDirectAgentCommand "pi"' ${minProfileModule}
      grep -F 'claudeCodePackage' ${minProfileModule}
      grep -F 'codexCliPackage' ${minProfileModule}
      grep -F 'piPackage' ${minProfileModule}
      grep -F 'directClaude = mkDirectAgentCommand "direct-claude" claudeCodePackage "claude";' ${minProfileModule}
      grep -F 'directCodex = mkDirectAgentCommand "direct-codex" codexCliPackage "codex";' ${minProfileModule}
      grep -F 'directPi = mkDirectAgentCommand "direct-pi" piPackage "pi";' ${minProfileModule}
      grep -F 'name = "pi-testing";' ${minProfileModule}
      grep -F 'PI_TESTING_AGENT_DIR:-$HOME/.pi-testing/agent' ${minProfileModule}
      grep -F 'PI_TESTING_SESSION_DIR:-$PI_CODING_AGENT_DIR/sessions' ${minProfileModule}
      grep -F 'PI_PACKAGE_DIR:-$HOME/.local/share/criomos/pi/package' ${minProfileModule}
      grep -F 'non-orchestrator.config.toml' ${minProfileModule}
      grep -F 'developer_instructions = ''${toJSON codexSkillReadDeduplicationInstruction}' ${minProfileModule}

      # Codex V1 is deliberate: collaboration is enabled and V2 remains off.
      grep -F 'features = {' ${minProfileModule}
      grep -F 'multi_agent = true;' ${minProfileModule}
      grep -F 'multi_agent_v2 = false;' ${minProfileModule}
      grep -F 'entryBefore [ "mergeCodexConfig" ]' ${minProfileModule}
      grep -F 'del(.features.collab)' ${minProfileModule}
      codexFixture="$TMPDIR/codex-config.toml"
      cat > "$codexFixture" <<'EOF'
    [features]
    collab = true
    multi_agent = true
    multi_agent_v2 = false
    EOF
      yq -p toml -o toml -i 'del(.features.collab)' "$codexFixture"
      test "$(yq -p toml '.features.multi_agent' "$codexFixture")" = true
      test "$(yq -p toml '.features.multi_agent_v2' "$codexFixture")" = false
      ! yq -p toml -e '.features | has("collab")' "$codexFixture" > /dev/null
      ! grep -F 'default_subagent_model' ${minProfileModule}
      ! grep -F 'default_subagent_reasoning_effort' ${minProfileModule}

      # User-level files override the three built-ins rather than relying on
      # inherited global subagent defaults.
      grep -F 'name = ''${toJSON name}' ${minProfileModule}
      grep -F 'model = ''${toJSON model}' ${minProfileModule}
      grep -F 'model_reasoning_effort = ''${toJSON effort}' ${minProfileModule}
      grep -F 'default = codexBuiltinAgent {' ${minProfileModule}
      grep -F 'worker = codexBuiltinAgent {' ${minProfileModule}
      grep -F 'explorer = codexBuiltinAgent {' ${minProfileModule}
      grep -F 'model = "gpt-5.6-terra";' ${minProfileModule}
      grep -F 'model = "gpt-5.6-luna";' ${minProfileModule}
      grep -F 'effort = "high";' ${minProfileModule}
      grep -F 'effort = "medium";' ${minProfileModule}
      grep -F '".codex/agents/default.toml".text = codexBuiltinAgentFiles.default;' ${minProfileModule}
      grep -F '".codex/agents/worker.toml".text = codexBuiltinAgentFiles.worker;' ${minProfileModule}
      grep -F '".codex/agents/explorer.toml".text = codexBuiltinAgentFiles.explorer;' ${minProfileModule}

      test -x ${agentProfilePath}/bin/claude
      test -x ${agentProfilePath}/bin/codex
      test -x ${agentProfilePath}/bin/pi
      test "$(readlink -f ${agentProfilePath}/bin/claude)" = "$(readlink -f ${claudeCodePackage}/bin/claude)"
      test "$(readlink -f ${agentProfilePath}/bin/codex)" = "$(readlink -f ${codexCliPackage}/bin/codex)"
      test "$(readlink -f ${agentProfilePath}/bin/pi)" = "$(readlink -f ${piPackage}/bin/pi)"
      test "$(${codexCliPackage}/bin/codex --version)" = "codex-cli 0.145.0"

      grep -F 'This source map does not grant tool permission' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js
      grep -F 'does not override project, role, skill, system, developer, or user instructions' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js
      grep -F 'must dispatch a worker/subagent' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js
      grep -F 'For ordinary implementation/support sessions that are permitted to inspect Pi directly' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js
      ! grep -F 'read only when the user asks about pi itself' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js
      ! grep -F 'When working on pi topics, read the docs and examples' ${piPackage}/lib/pi-monorepo/packages/coding-agent/dist/core/system-prompt.js

      touch "$out"
  ''
