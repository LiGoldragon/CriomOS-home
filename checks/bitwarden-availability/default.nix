{ pkgs, ... }:
let
  lib = pkgs.lib;
  bitwardenModule = ../../modules/home/profiles/min/bitwarden.nix;

  aggregate = import ../../modules/home/default.nix {
    flake = null;
    inputs = null;
  };
  aggregateImports =
    (aggregate {
      config = { };
      inherit lib;
    }).imports;
  importsBitwardenModule = builtins.any (
    module: toString module == toString bitwardenModule
  ) aggregateImports;

  mkProfilePackages =
    size:
    (lib.evalModules {
      specialArgs = {
        inherit pkgs;
        user = { inherit size; };
      };
      modules = [
        bitwardenModule
        (
          { lib, ... }:
          {
            options.home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
          }
        )
      ];
    }).config.home.packages;

  disabledPackages = mkProfilePackages {
    min = false;
    medium = false;
  };
  minimumPackages = mkProfilePackages {
    min = true;
    medium = false;
  };
  mediumPackages = mkProfilePackages {
    min = true;
    medium = true;
  };

  packageNames = packages: map lib.getName packages;
  disabledNames = packageNames disabledPackages;
  minimumNames = packageNames minimumPackages;
  mediumNames = packageNames mediumPackages;

  mediumProfile = pkgs.symlinkJoin {
    name = "bitwarden-medium-profile-witness";
    paths = mediumPackages;
  };
in
assert importsBitwardenModule;
assert disabledNames == [ ];
assert minimumNames == [ "bitwarden-cli" ];
assert builtins.elem "bitwarden-cli" mediumNames;
assert builtins.elem "bitwarden-desktop" mediumNames;
assert builtins.length mediumNames == 2;
pkgs.runCommand "bitwarden-availability"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    test -x "${mediumProfile}/bin/bw"
    test -x "${mediumProfile}/bin/bitwarden"

    desktop_launcher="$(find "${mediumProfile}/share/applications" -maxdepth 1 -type f -name '*.desktop' -print -quit)"
    test -n "$desktop_launcher"
    grep -Eq '^Exec=.*bitwarden' "$desktop_launcher"

    touch "$out"
  ''
