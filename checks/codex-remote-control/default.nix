{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  codexCliPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  corePackagesModule = ../../modules/home/core-packages.nix;
  codexRemoteControlModule = ../../modules/home/profiles/min/agent-intercom.nix;
  mkConfiguration =
    user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs user;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = {
          node.services = [ ];
          users.${user.name} = user;
        };
      };
      modules = [
        corePackagesModule
        codexRemoteControlModule
        {
          home = {
            username = user.name;
            homeDirectory = "/home/${user.name}";
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  codexUser = {
    name = "codex-remote-control-test";
    size.min = true;
  };
  nonCodexUser = {
    name = "codex-remote-control-test";
    size.min = false;
  };
  secondCodexUser = {
    name = "codex-remote-control-second";
    size.min = true;
  };
  configuration = mkConfiguration codexUser;
  nonCodexConfiguration = mkConfiguration nonCodexUser;
  secondConfiguration = mkConfiguration secondCodexUser;
  embeddedUserName = "embedded-codex-test";
  embeddedHorizon = {
    node.services = [ ];
    users.${embeddedUserName} = {
      name = embeddedUserName;
      size.min = true;
    };
  };
  embeddedConfiguration = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      inputs.home-manager.nixosModules.home-manager
      {
        system.stateVersion = "26.05";
        users.users.${embeddedUserName}.isNormalUser = true;
        home-manager = {
          useGlobalPkgs = true;
          extraSpecialArgs = {
            inherit inputs pkgs;
            horizon = embeddedHorizon;
            hexis = inputs.hexis.packages.${system}.default;
          };
          sharedModules = [
            corePackagesModule
            codexRemoteControlModule
          ];
          users.${embeddedUserName} = {
            _module.args.user = embeddedHorizon.users.${embeddedUserName};
            home = {
              username = embeddedUserName;
              homeDirectory = "/home/${embeddedUserName}";
              stateVersion = "26.05";
            };
          };
        };
      }
    ];
  };
  remoteControlService = configuration.systemd.user.services.codex-remote-control;
in
assert configuration.systemd.user.services ? codex-remote-control;
assert !(nonCodexConfiguration.systemd.user.services ? codex-remote-control);
assert
  embeddedConfiguration.config.home-manager.users.${embeddedUserName}.systemd.user.services
  ? codex-remote-control;
assert remoteControlService.Service.UMask == "0077";
assert remoteControlService.Service.Restart == "always";
assert remoteControlService.Service.WorkingDirectory == "/home/codex-remote-control-test/primary";
assert
  secondConfiguration.systemd.user.services.codex-remote-control.Service.WorkingDirectory
  == "/home/codex-remote-control-second/primary";
assert builtins.length remoteControlService.Service.ExecStart == 1;
pkgs.runCommand "codex-remote-control-contract" { } ''
  set -eu
  test "${builtins.head remoteControlService.Service.ExecStart}" = "${codexCliPackage}/bin/codex app-server --remote-control --listen unix://"
  touch "$out"
''
