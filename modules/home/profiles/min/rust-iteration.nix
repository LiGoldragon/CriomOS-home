# A Home on the builder defers to CriomOS for Cargo and its target directory.
# Other Homes carry the remote-only wrapper.
{
  config,
  lib,
  rustToolchain,
  ...
}:
let
  cfg = config.criomosHome.rustIteration;
in
{
  options.criomosHome.rustIteration = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the host's iteration toolchain in place of the remote-only wrapper.";
    };
    toolchain = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      readOnly = true;
      default = if cfg.enable then null else rustToolchain;
      description = "The remote-only wrapper when the system supplies no iteration toolchain.";
    };
  };
}
