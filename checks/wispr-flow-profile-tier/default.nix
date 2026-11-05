{ inputs, pkgs, ... }:
let
  wisprFlowModule = ../../modules/home/profiles/min/wispr-flow.nix;
  profilePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = package: pkgs.lib.getName package == "wispr-flow";
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
    size = "Min";
  };
  mediumHome = mkHome {
    name = "medium-profile-check";
    size = "Medium";
  };
  maximumHome = mkHome {
    name = "maximum-profile-check";
    size = "Max";
  };
in
let
  packagePaths = home: map (package: package.drvPath) home.config.home.packages;
  belowMediumPackages = packagePaths belowMediumHome;
  mediumPackages = packagePaths mediumHome;
  maximumPackages = packagePaths maximumHome;
  wisprPackage = builtins.head (
    pkgs.lib.subtractLists belowMediumHome.config.home.packages mediumHome.config.home.packages
  );
  wisprStatus = "${wisprPackage}/bin/wispr-flow-status";
  wisprService = mediumHome.config.systemd.user.services.wispr-flow;
in
assert builtins.length (pkgs.lib.subtractLists belowMediumPackages mediumPackages) == 1;
assert pkgs.lib.subtractLists mediumPackages belowMediumPackages == [ ];
assert mediumPackages == maximumPackages;
assert !(builtins.hasAttr "wispr-flow" belowMediumHome.config.systemd.user.services);
assert wisprService.Unit.After == [ "graphical-session.target" ];
assert wisprService.Unit.PartOf == [ "graphical-session.target" ];
assert wisprService.Service.ExecStart == [ "${wisprPackage}/bin/wispr-flow" ];
assert wisprService.Service.Restart == "on-failure";
assert wisprService.Service.RestartSec == "2s";
assert wisprService.Install.WantedBy == [ "graphical-session.target" ];
pkgs.runCommand "wispr-flow-profile-tier" { } ''
  test -x ${wisprPackage}/bin/wispr-flow
  test -x ${wisprStatus}
  touch "$out"
''
