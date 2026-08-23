{ inputs, pkgs, ... }:

# llm-agents now packages Claude Code 2.1.241, so retain its authoritative
# wrapper unchanged rather than carrying a local source/version override.
inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
