{
  lib,
  pkgs,
  inputs ? null,
  ...
}:
{
  options.criomos.corePackages = {
    codex = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../owned-agents/codex { inherit inputs; }";
      description = "The canonical Codex CLI derivation used by every Home consumer.";
    };

    claude = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../owned-agents/claude-code { inherit inputs; };
      defaultText = lib.literalExpression "pkgs.callPackage ../../owned-agents/claude-code { inherit inputs; }";
      description = "The canonical Claude Code CLI derivation used by every Home consumer.";
    };

    flowId = lib.mkOption {
      type = lib.types.package;
      default = inputs.harness.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.harness.packages.<system>.default";
      description = "The canonical parent-flow identity helper used by Home consumers.";
    };
  };
}
