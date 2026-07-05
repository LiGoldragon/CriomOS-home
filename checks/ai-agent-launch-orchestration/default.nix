{ pkgs, ... }:

let
  minProfileModule = ../../modules/home/profiles/min/default.nix;
in
pkgs.runCommand "ai-agent-launch-orchestration" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  set -eu

  ! grep -F 'defaultOrchestrationInstruction =' ${minProfileModule}
  ! grep -F 'Default launch mode: parent orchestrator.' ${minProfileModule}
  ! grep -F 'criomos-default-orchestration-instructions.md' ${minProfileModule}
  ! grep -F 'codex-default-orchestration-developer-instructions.toml-value' ${minProfileModule}
  ! grep -F 'append-system-prompt "$(cat' ${minProfileModule}
  ! grep -F 'developer_instructions=$(cat' ${minProfileModule}
  ! grep -F 'CRIOMOS_AGENT_MODE' ${minProfileModule}
  ! grep -F 'PI_SUBAGENT_CHILD' ${minProfileModule}
  ! grep -F 'CLAUDE_CODE_SUBAGENT' ${minProfileModule}

  grep -F 'claudeCommand = mkDirectAgentCommand "claude" claudeCodePackage "claude";' ${minProfileModule}
  grep -F 'codexCommand = mkDirectAgentCommand "codex" codexCliPackage "codex";' ${minProfileModule}
  grep -F 'piCommand = mkDirectAgentCommand "pi" piPackage "pi";' ${minProfileModule}
  grep -F 'directClaude = mkDirectAgentCommand "direct-claude" claudeCodePackage "claude";' ${minProfileModule}
  grep -F 'directCodex = mkDirectAgentCommand "direct-codex" codexCliPackage "codex";' ${minProfileModule}
  grep -F 'directPi = mkDirectAgentCommand "direct-pi" piPackage "pi";' ${minProfileModule}
  grep -F 'name = "pi-testing";' ${minProfileModule}
  grep -F 'PI_TESTING_AGENT_DIR:-$HOME/.pi-testing/agent' ${minProfileModule}
  grep -F 'PI_TESTING_SESSION_DIR:-$PI_CODING_AGENT_DIR/sessions' ${minProfileModule}
  grep -F 'PI_PACKAGE_DIR:-$HOME/.local/share/criomos/pi/package' ${minProfileModule}
  grep -F 'non-orchestrator.config.toml' ${minProfileModule}
  grep -F 'developer_instructions = ''${toJSON codexSkillReadDeduplicationInstruction}' ${minProfileModule}

  touch "$out"
''
