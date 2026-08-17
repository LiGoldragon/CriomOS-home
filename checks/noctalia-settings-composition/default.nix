{ pkgs, inputs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hexis = pkgs.writeShellScriptBin "hexis" "exit 0";
      horizon.node.behavesAs.edge = true;
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.noctalia.homeModules.default
      ../../modules/home/profiles/min/sfwbar.nix
      {
        home = {
          username = "noctalia-check";
          homeDirectory = "/home/noctalia-check";
          stateVersion = "26.11";
        };

        # Exercise the actual upstream dark-mode definition that caused the
        # activation build conflict, rather than a hand-written approximation.
        stylix = {
          enable = true;
          polarity = "dark";
          base16Scheme = ../../modules/home/ignis.yaml;
        };

        programs.noctalia.validateConfig = false;
      }
    ];
  };
  settings = homeConfiguration.config.programs.noctalia.settings;
in
assert pkgs.lib.assertMsg (
  settings.theme.mode == "auto"
) "the declared Noctalia theme mode must override Stylix's dark-mode target";
assert pkgs.lib.assertMsg (
  settings.theme.source == "wallpaper"
) "the declared Noctalia theme source must override Stylix's custom-palette target";
assert pkgs.lib.assertMsg (
  settings.theme.wallpaper_scheme == "m3-rainbow"
) "the declared Noctalia wallpaper scheme must remain effective";
assert pkgs.lib.assertMsg (
  settings.bar.widgets.margin_ends == 0
) "the Noctalia bar must remain configured for full output width";
pkgs.runCommand "noctalia-settings-composition" { } ''
  touch "$out"
''
