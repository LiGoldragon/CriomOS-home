{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.contextSkills;
  skills = pkgs.callPackage ../../../../packages/context-skills { inherit inputs; };
in
{
  options.criomosHome.contextSkills.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.criomosHome.curriculum.enable;
    description = "Install every context module as a skill in the Primary workspace's harness skill directories.";
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.listToAttrs (
      map (surface: {
        name = "primary/${surface}";
        value.source = "${skills}/${surface}";
      }) skills.surfaces
    );
  };
}
