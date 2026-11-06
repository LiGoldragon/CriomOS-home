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
in
{
  # The Flow Nexus runs as one declared unit per version (flow-nexus-version.nix);
  # this module holds what every Flow version shares.
  options.criomosHome.flow.enable = lib.mkOption {
    type = lib.types.bool;
    default = builtins.elem "AgentStack" user.capabilities;
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
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
