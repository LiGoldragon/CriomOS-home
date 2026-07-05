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
pkgs.runCommand "ai-agent-launch-orchestration" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
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

  test -x ${agentProfilePath}/bin/claude
  test -x ${agentProfilePath}/bin/codex
  test -x ${agentProfilePath}/bin/pi
  test "$(readlink -f ${agentProfilePath}/bin/claude)" = "$(readlink -f ${claudeCodePackage}/bin/claude)"
  test "$(readlink -f ${agentProfilePath}/bin/codex)" = "$(readlink -f ${codexCliPackage}/bin/codex)"
  test "$(readlink -f ${agentProfilePath}/bin/pi)" = "$(readlink -f ${piPackage}/bin/pi)"

  touch "$out"
''
