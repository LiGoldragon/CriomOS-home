{
  config,
  lib,
  pkgs,
  user,
  ...
}:
# `flow` and `flow-meta` are thin wrappers over the versioned CLIs each
# deployed Flow Nexus installs (flow-0.44, flow-0.48, flow-0.49, flow-meta-0.44,
# flow-meta-0.48, flow-meta-0.49). Hooks and seats keep calling `flow`; the version they
# reach is the one value criomosHome.flowCli.version.
let
  cfg = config.criomosHome.flowCli;
  deployed = {
    "0.44" = config.criomosHome.flow.enable;
    "0.48" = config.criomosHome.flow048.enable;
    "0.49" = config.criomosHome.flow049.enable;
    "0.50" = config.criomosHome.flow050.enable;
  };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  wrapper =
    name:
    pkgs.writeShellScriptBin name ''
      exec ${name}-${cfg.version} "$@"
    '';
in
{
  options.criomosHome.flowCli.version = lib.mkOption {
    type = lib.types.enum [
      "0.44"
      "0.48"
      "0.49"
      "0.50"
    ];
    default = "0.44";
    description = "The Flow Nexus version `flow` and `flow-meta` reach.";
  };
  config = lib.mkIf (sizeAtLeast "Min" && (deployed."0.44" || deployed."0.48" || deployed."0.49" || deployed."0.50")) {
    assertions = [
      {
        assertion = deployed.${cfg.version};
        message = "criomosHome.flowCli.version ${cfg.version} names a Flow Nexus version this home does not deploy";
      }
    ];
    home.packages = [
      (wrapper "flow")
      (wrapper "flow-meta")
    ];
  };
}
