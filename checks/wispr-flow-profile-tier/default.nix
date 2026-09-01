{ inputs, pkgs, ... }:
let
  wisprFlowModule = ../../modules/home/profiles/min/wispr-flow.nix;

  mkHome =
    user:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs user; };
      modules = [
        wisprFlowModule
        {
          home = {
            username = "profile-tier-check";
            homeDirectory = "/home/profile-tier-check";
            stateVersion = "26.05";
          };
        }
      ];
    };

  belowMediumHome = mkHome {
    name = "below-medium-profile-check";
    size = {
      medium = false;
      max = false;
    };
  };
  mediumHome = mkHome {
    name = "medium-profile-check";
    size = {
      medium = true;
      max = false;
    };
  };
  maximumHome = mkHome {
    name = "maximum-profile-check";
    size = {
      medium = true;
      max = true;
    };
  };
in
assert belowMediumHome.config.home.packages == [ ];
assert builtins.length mediumHome.config.home.packages == 1;
assert builtins.length maximumHome.config.home.packages == 1;
assert (builtins.head mediumHome.config.home.packages).drvPath != "";
assert (builtins.head maximumHome.config.home.packages).drvPath != "";
pkgs.runCommand "wispr-flow-profile-tier" { } ''
  touch "$out"
''
