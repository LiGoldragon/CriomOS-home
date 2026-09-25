{ inputs, pkgs, ... }:
let
  horizon = {
    users = [
      {
        name = "opencode-check";
        size = "Min";
      }
    ];
    node = {
      capabilities = [ { kind = "openCodeTesting"; } ];
      keys.yggdrasil.address = "200:abcd::1";
    };
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit horizon;
        user = builtins.head horizon.users;
      };
      modules = [
        ../../modules/home/profiles/min/opencode.nix
        {
          home = {
            username = "opencode-check";
            homeDirectory = "/home/opencode-check";
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  profile = pkgs.buildEnv {
    name = "opencode-testing-home-profile";
    paths = configuration.home.packages;
  };
  packageName = package: package.pname or (package.name or "");
  hasPackage = name: builtins.any (package: packageName package == name) configuration.home.packages;
  service = configuration.systemd.user.services.opencode-testing;
in
assert hasPackage "opencode";
assert hasPackage "opencode-testing-login";
assert service.Unit.ConditionPathExists == "/run/secrets/opencodeServerPassword";
assert
  service.Service.LoadCredential
  == [ "opencode-server-password:/run/secrets/opencodeServerPassword" ];
assert service.Service.Environment != [ ];
pkgs.runCommand "opencode-testing-home-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      profile
    ];
  }
  ''
    set -eu
    test "$( ${profile}/bin/opencode --version )" = ${pkgs.lib.escapeShellArg pkgs.opencode.version}
    ${profile}/bin/opencode-testing-login models --help >/dev/null
    touch "$out"
  ''
