{ pkgs, inputs }:
let
  claudeCode = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

  claudeShared = pkgs.writeShellScriptBin "claude" ''
    set -euo pipefail

    arguments=(--bare)
    search_directory="$PWD"

    while true; do
      if [ -f "$search_directory/CLAUDE.md" ] || [ -f "$search_directory/AGENTS.md" ]; then
        arguments+=(--add-dir "$search_directory")
        break
      fi

      if [ "$search_directory" = "/" ]; then
        break
      fi

      search_directory="$(dirname "$search_directory")"
    done

    exec ${claudeCode}/bin/claude "''${arguments[@]}" "$@"
  '';

  claudePrivateMemory = pkgs.writeShellScriptBin "claude-private-memory" ''
    exec ${claudeCode}/bin/claude "$@"
  '';
in
pkgs.symlinkJoin {
  name = "claude-shared";
  paths = [
    claudeShared
    claudePrivateMemory
  ];
  passthru = {
    inherit claudeCode;
  };
}
