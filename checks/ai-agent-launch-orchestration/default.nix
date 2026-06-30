{ pkgs, ... }:

let
  minProfileModule = ../../modules/home/profiles/min/default.nix;
in
pkgs.runCommand "ai-agent-launch-orchestration" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  set -eu

  grep -F 'defaultOrchestrationInstruction =' ${minProfileModule}
  grep -F 'Default launch mode: parent orchestrator.' ${minProfileModule}

  grep -F 'name = "claude";' ${minProfileModule}
  grep -F 'exec ''${claudeCodePackage}/bin/claude --append-system-prompt "$(cat ''${defaultOrchestrationInstructionFile})" "$@"' ${minProfileModule}
  grep -F 'name = "codex";' ${minProfileModule}
  grep -F 'developer_instructions=$(cat ''${codexDefaultDeveloperInstructionsTomlValue})' ${minProfileModule}
  grep -F 'exec ''${codexCliPackage}/bin/codex --config "developer_instructions=$developer_instructions" "$@"' ${minProfileModule}
  grep -F 'name = "pi";' ${minProfileModule}
  grep -F 'exec ''${piPackage}/bin/pi --append-system-prompt "$(cat ''${defaultOrchestrationInstructionFile})" "$@"' ${minProfileModule}

  grep -F 'directClaude = mkDirectAgentCommand "direct-claude" claudeCodePackage "claude";' ${minProfileModule}
  grep -F 'directCodex = mkDirectAgentCommand "direct-codex" codexCliPackage "codex";' ${minProfileModule}
  grep -F 'directPi = mkDirectAgentCommand "direct-pi" piPackage "pi";' ${minProfileModule}
  grep -F 'CRIOMOS_AGENT_MODE' ${minProfileModule}
  grep -F 'non-orchestrator.config.toml' ${minProfileModule}

  grep -F 'PI_SUBAGENT_CHILD' ${minProfileModule}
  grep -F -- '--agent=*|--agents=*|--system-prompt=*|--append-system-prompt=*' ${minProfileModule}
  grep -F -- '--profile=non-orchestrator|-p=non-orchestrator|--config=developer_instructions=*|-c=developer_instructions=*' ${minProfileModule}
  grep -F -- '--system-prompt=*|--append-system-prompt=*' ${minProfileModule}

  touch "$out"
''
