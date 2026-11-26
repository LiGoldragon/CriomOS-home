{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.flow;
  system = pkgs.stdenv.hostPlatform.system;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  claudeAgentDescription = ../../../../lib/claude-flow-agent-description;
  installClaudeAgentDescription = pkgs.writeShellApplication {
    name = "install-claude-flow-agent-description";
    runtimeInputs = [ pkgs.coreutils pkgs.diffutils ];
    text = ''
      home=$1
      claude="$home/.claude"
      skills="$claude/skills"
      plugin="$skills/flow-agent-description"
      source=${claudeAgentDescription}

      case "$home" in /*) ;; *) exit 1 ;; esac
      ancestor=$home
      while test "$ancestor" != /; do
        test -d "$ancestor"
        test ! -L "$ancestor"
        ancestor=$(dirname -- "$ancestor")
      done

      verify_directory() {
        test -d "$1"
        test ! -L "$1"
        test -O "$1"
      }

      for directory in "$claude" "$skills"; do
        mkdir -p -m 0700 -- "$directory"
        verify_directory "$directory"
      done

      code=(.claude-plugin/plugin.json hooks/hooks.json hooks/register.js)
      data=agent-description.txt

      verify_plugin() {
        for directory in "$plugin" "$plugin/.claude-plugin" "$plugin/hooks"; do
          verify_directory "$directory"
        done

        shopt -s dotglob nullglob
        entries=("$plugin"/*)
        test "''${#entries[@]}" -eq 3
        entries=("$plugin/.claude-plugin"/*)
        test "''${#entries[@]}" -eq 1
        entries=("$plugin/hooks"/*)
        test "''${#entries[@]}" -eq 2

        for file in "''${code[@]}" "$data"; do
          test -f "$plugin/$file"
          test ! -L "$plugin/$file"
          test -O "$plugin/$file"
        done
        for file in "''${code[@]}"; do
          cmp "$source/$file" "$plugin/$file"
        done
        test -w "$plugin/$data"
      }

      if test -e "$plugin" || test -L "$plugin"; then
        verify_plugin
        exit
      fi

      staged=$(mktemp -d "$claude/.flow-agent-description.XXXXXXXX")
      trap 'rm -rf -- "$staged"' EXIT
      for file in "''${code[@]}" "$data"; do
        install -D -m 0600 -- "$source/$file" "$staged/$file"
      done
      mv -T --no-clobber -- "$staged" "$plugin"
      verify_plugin
    '';
  };
in
{
  # The Flow Nexus runs as one declared unit per version (flow-nexus-place.nix);
  # this module holds what every Flow version shares.
  options.criomosHome.flow.enable = lib.mkOption {
    type = lib.types.bool;
    default = builtins.elem "AgentStack" user.capabilities;
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    # The editable passage is seeded once; later activations verify the mod
    # code without overwriting the passage or restarting a Claude session.
    home.activation.claudeFlowAgentDescription = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe installClaudeAgentDescription} ${lib.escapeShellArg config.home.homeDirectory}
    '';

    # Flow refreshes a flow past its model's threshold when it rests, so
    # no harness compacts a resting flow. Claude Code compacts an idle
    # session of 200,000 tokens or more as its prompt cache nears expiry;
    # this turns that off for every Claude session. Its remaining automatic
    # compaction is at the window less 33,000 tokens.
    home.activation.claudeLeavesRestToFlow = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs;
      hexis = inputs.hexis.packages.${system}.default;
      file = "$HOME/.claude/settings.json";
      declared.idleCompaction = false;
      modes."/idleCompaction" = "always";
    };
  };
}
