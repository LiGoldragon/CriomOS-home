# Cargo for iteration (Fable ruling bwv8). The host that carries it runs a
# real Cargo in a work tree of the synchronized folder; every other host
# keeps the remote-only wrapper (packages/rust-toolchain). The real Cargo is
# build-base's toolchain, the one the Nix builds compile with, so an
# iteration and a gate use the same compiler. Its target directory lies
# outside the synchronized folder. Nothing iteration compiles is kept: what
# is kept stays a Nix derivation. CriomOS enables it for a host
# (criomos.rustIteration in CriomOS).
{
  config,
  lib,
  pkgs,
  inputs,
  rustToolchain,
  ...
}:
let
  cfg = config.criomosHome.rustIteration;
  iterationToolchain = inputs.base.packages.${pkgs.stdenv.hostPlatform.system}.toolchain;
in
{
  options.criomosHome.rustIteration = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Carry build-base's real Cargo for iteration in place of the remote-only wrapper.";
    };
    targetDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/cargo-iteration";
      description = "Where an iteration's Cargo writes its build output; outside the synchronized folder.";
    };
    toolchain = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = if cfg.enable then iterationToolchain else rustToolchain;
      description = "The Rust toolchain the user's profile carries: build-base's for iteration, else the wrapper.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".cargo/config.toml".text = ''
      [build]
      target-dir = "${cfg.targetDirectory}"
    '';
  };
}
