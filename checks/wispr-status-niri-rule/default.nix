{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      constants = inputs.criomos-lib.lib.constants;
      horizon.node.behavesAs.edge = true;
      user.useFastRepeat = false;
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      ../../modules/home/profiles/min/niri.nix
      {
        home = {
          username = "niri-status-check";
          homeDirectory = "/home/niri-status-check";
          stateVersion = "26.05";
        };
        programs.niri.package = pkgs.niri;
        stylix = {
          enable = true;
          polarity = "dark";
          base16Scheme = ../../modules/home/ignis.yaml;
        };
      }
    ];
  };
  generatedConfig = homeConfiguration.config.programs.niri.finalConfig;
in
assert lib.assertMsg
  (lib.hasInfix ''match app-id="^wispr-flow$" title="^(Status|Flow Status Indicator)$"'' generatedConfig)
  "the generated Niri config must scope the Status repair to Wispr's app-id and its packed and live titles";
assert lib.assertMsg (lib.hasInfix "draw-border-with-background false" generatedConfig)
  "the scoped Wispr Status rule must prevent Niri from filling the transparent Status surface";
assert lib.assertMsg (builtins.any
  (
    rule:
    rule.draw-border-with-background == false
    && rule.focus-ring.enable == false
    && builtins.any (
      match: match.app-id == "^wispr-flow$" && match.title == "^(Status|Flow Status Indicator)$"
    ) rule.matches
  )
  homeConfiguration.config.programs.niri.settings.window-rules
) "the scoped Wispr Status rule must disable the focus ring";
pkgs.runCommand "wispr-status-niri-rule" { nativeBuildInputs = [ pkgs.niri ]; } ''
  ${pkgs.niri}/bin/niri validate -c ${homeConfiguration.config.xdg.configFile.niri-config.source}
  touch "$out"
''
