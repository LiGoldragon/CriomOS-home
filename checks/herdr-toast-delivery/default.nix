{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        size = "Min";
        useColemak = false;
        hasPublicKey = false;
        gitSigningKey = "";
        matrixId = "";
        isMultimediaDev = false;
        emailAddress = "herdr-toast-check@example.invalid";
        githubId = "herdr-toast-check";
        name = "herdr-toast-check";
        publicKeys = [ ];
      };
      horizon.node = {
        name = "herdr-toast-check";
        machine.architecture = "x86_64";
      };
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [
      ../../modules/home/profiles/min/default.nix
      {
        home = {
          username = "herdr-toast-check";
          homeDirectory = "/home/herdr-toast-check";
          stateVersion = "26.11";
        };
      }
    ];
  };
  configToml = builtins.readFile homeConfiguration.config.xdg.configFile."herdr/config.toml".source;
  parsedConfigToml = builtins.fromTOML configToml;
in
assert parsedConfigToml.ui.toast.delivery == "terminal";
pkgs.runCommand "herdr-toast-delivery" { } ''
  touch "$out"
''
