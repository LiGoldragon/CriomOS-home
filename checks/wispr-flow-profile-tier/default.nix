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

  mediumHome = mkHome {
    name = "medium-profile-check";
    size.max = false;
  };
  maximumHome = mkHome {
    name = "maximum-profile-check";
    size.max = true;
  };
in
assert mediumHome.config.home.packages == [ ];
assert builtins.length maximumHome.config.home.packages == 1;
pkgs.runCommand "wispr-flow-profile-tier" { } ''
  touch "$out"
''
