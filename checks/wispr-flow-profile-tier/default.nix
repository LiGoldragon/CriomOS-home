{ inputs, pkgs, ... }:
let
  wisprFlowModule = ../../modules/home/profiles/min/wispr-flow.nix;
  profilePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = package: pkgs.lib.getName package == "wispr-flow";
  };
  runtimeInputs = profilePkgs.callPackage "${inputs.wispr-flow-linux}/nix/runtime-inputs.nix" { };
  providerWispr = profilePkgs.callPackage "${inputs.wispr-flow-linux}/nix/wispr-flow.nix" {
    inherit runtimeInputs;
  };

  mkHome =
    user:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = profilePkgs;
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
let
  packagePaths = home: map (package: package.drvPath) home.config.home.packages;
  belowMediumPackages = packagePaths belowMediumHome;
  mediumPackages = packagePaths mediumHome;
  maximumPackages = packagePaths maximumHome;
  wisprPackage = builtins.head (pkgs.lib.subtractLists belowMediumHome.config.home.packages mediumHome.config.home.packages);
  wisprStatus = "${wisprPackage}/bin/wispr-flow-status";
in
assert builtins.length (pkgs.lib.subtractLists belowMediumPackages mediumPackages) == 1;
assert pkgs.lib.subtractLists mediumPackages belowMediumPackages == [ ];
assert mediumPackages == maximumPackages;
assert providerWispr.version == "1.6.774+criomos.5";
assert pkgs.lib.hasSuffix "/bin/wispr-flow-status" wisprStatus;
pkgs.runCommand "wispr-flow-profile-tier" { } ''
  touch "$out"
''
