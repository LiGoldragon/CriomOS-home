{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  maxProfile = ../../modules/home/profiles/max/default.nix;
  maxDirectory = toString ../../modules/home/profiles/max;
  checksDirectory = toString ../.;
  retiredModuleFile =
    lib.concatStringsSep "-" [
      "capture"
      "card"
      "virtual"
      "camera"
    ]
    + ".nix";
  retiredCheckDirectory = lib.concatStringsSep "-" [
    "capture"
    "card"
    "virtual"
    "camera"
  ];
  retiredService = lib.concatStringsSep "-" [
    "capture"
    "card"
    "virtual"
    "camera"
  ];
  retiredBridge = lib.concatStringsSep "-" [
    "criomos"
    "capture"
    "card"
    "virtual"
    "camera"
    "bridge"
  ];
  retiredModulePath = "${maxDirectory}/${retiredModuleFile}";

  homeAggregate = import ../../modules/home/default.nix {
    flake = null;
    inputs = null;
  };
  aggregateImports =
    (homeAggregate {
      config = { };
      inherit lib;
    }).imports;
  importsRetiredModule = builtins.any (module: toString module == retiredModulePath) aggregateImports;

  fakeInputs = {
    self.packages.${system}.traycer = pkgs.hello;
    mentci-egui.packages.${system}.default = pkgs.hello;
    hexis.lib.wrapWithHexis = { package, ... }: package;
  };

  mkHome =
    {
      large,
      edge,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inputs = fakeInputs;
        hexis = pkgs.hello;
        horizon.node.behavesAs.edge = edge;
        user = {
          isMultimediaDev = false;
          size = {
            inherit large;
            max = false;
          };
        };
      };
      modules = [
        maxProfile
        {
          home = {
            username = "profile-absence-check";
            homeDirectory = "/home/profile-absence-check";
            stateVersion = "26.05";
          };
        }
      ];
    };

  largeEdge =
    (mkHome {
      large = true;
      edge = true;
    }).config;
  ordinary =
    (mkHome {
      large = false;
      edge = false;
    }).config;
  packageName = package: package.pname or (package.name or "");
  hasBridge =
    config: builtins.any (package: packageName package == retiredBridge) config.home.packages;
  flakeSource = builtins.readFile ../../flake.nix;
in
assert !(builtins.pathExists retiredModulePath);
assert !(builtins.pathExists "${checksDirectory}/${retiredCheckDirectory}");
assert !importsRetiredModule;
assert !(lib.hasInfix retiredService flakeSource);
assert !(largeEdge.systemd.user.services ? ${retiredService});
assert !(ordinary.systemd.user.services ? ${retiredService});
assert !(hasBridge largeEdge);
assert !(hasBridge ordinary);
pkgs.runCommand "home-profile-absence" { } ''
  touch "$out"
''
