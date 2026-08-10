{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      {
        home = {
          username = "session-variable-fixture";
          homeDirectory = "/home/session-variable-fixture";
          stateVersion = "26.05";
          sessionVariables.CRIOMOS_SESSION_VARIABLE_WITNESS = "configured";
        };
        programs.zsh.enable = true;
      }
    ];
  };
  activationPackage = homeConfiguration.activationPackage;
in
pkgs.runCommand "home-session-variables"
  {
    inherit activationPackage;
  }
  ''
    set -eu

    sessionVariables="$activationPackage/etc/profile.d/hm-session-vars.sh"
    test -f "$sessionVariables"
    grep -F 'export CRIOMOS_SESSION_VARIABLE_WITNESS="configured"' "$sessionVariables"
    touch "$out"
  ''
