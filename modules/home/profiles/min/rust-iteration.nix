# CriomOS owns the builder's Cargo in the system profile. A Home on that
# host supplies the user's iteration directory and defers to the host
# toolchain; other Homes carry the remote-only wrapper.
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
    targetDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/cargo-iteration";
      description = "Where an iteration's Cargo writes its build output; outside the synchronized folder.";
    };
    toolchain = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      readOnly = true;
      default = if cfg.enable then null else rustToolchain;
      description = "The remote-only wrapper when the system supplies no iteration toolchain.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".cargo/config.toml".text = ''
      [build]
      target-dir = "${cfg.targetDirectory}"
    '';
  };
}
