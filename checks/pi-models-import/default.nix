{ pkgs, ... }:
let
  lib = pkgs.lib;
  minProfile = ../../modules/home/profiles/min;
  minModule = import minProfile {
    inherit lib;
    pkgs = null;
    criomos-lib = null;
    user = { size = "Min"; };
    horizon = { node = { name = "check"; }; };
    config = { };
    inputs = { };
    hexis = null;
    rustToolchain = null;
  };
  minImports = minModule.imports or [ ];
  piModels = toString ../../modules/home/profiles/min/pi-models.nix;
  piModelsSource = builtins.readFile ../../modules/home/profiles/min/pi-models.nix;
  activationNames = [ "mergePiModels" "mergePiTestingModels" ];
in
assert builtins.any (module: toString module == piModels) minImports;
assert builtins.all (name: lib.hasInfix "home.activation.${name}" piModelsSource) activationNames;
pkgs.runCommand "pi-models-import" { } ''
  touch "$out"
''
