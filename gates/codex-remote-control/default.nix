{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  codexCliPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  corePackagesModule = ../../modules/home/core-packages.nix;
  guardModule = ../../modules/home/profiles/min/default-opener.nix;
  codexRemoteControlModule = ../../modules/home/profiles/min/codex-remote-control.nix;
  mkConfiguration =
    user: guardEnabled:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = {
          node.services = [ ];
          users = [ user ];
        };
        inherit user;
      };
      modules = [
        corePackagesModule
        guardModule
        codexRemoteControlModule
        {
          criomosHome.remoteBuildCommandGuard.enable = guardEnabled;
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
    size = "Min";
  };
  nonCodexUser = {
    name = "codex-remote-control-test";
    size = "Zero";
  };
  secondCodexUser = {
    name = "codex-remote-control-second";
    size = "Min";
  };
  configuration = mkConfiguration codexUser true;
  disabledConfiguration = mkConfiguration codexUser false;
  nonCodexConfiguration = mkConfiguration nonCodexUser false;
  secondConfiguration = mkConfiguration secondCodexUser true;
  embeddedUserName = "embedded-codex-test";
  embeddedHorizon = {
    node.services = [ ];
    users = [
      {
        name = embeddedUserName;
        size = "Min";
      }
    ];
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
            _module.args.user = builtins.head embeddedHorizon.users;
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
  activationPackage = configuration.home.activationPackage;
in
assert configuration.systemd.user.services ? codex-remote-control;
assert !(nonCodexConfiguration.systemd.user.services ? codex-remote-control);
assert !(configuration.home.activation ? mergeAgentIntercomCodexMcp);
assert !(configuration.home.activation ? mergeAgentIntercomClaudeMcp);
assert
  embeddedConfiguration.config.home-manager.users.${embeddedUserName}.systemd.user.services
  ? codex-remote-control;
assert remoteControlService.Service.UMask == "0077";
assert remoteControlService.Service.Restart == "always";
assert
  remoteControlService.Service.Environment == [
    "PATH=${configuration.criomosHome.remoteBuildCommandGuard.directory}:%h/.local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin"
  ];
assert
  (disabledConfiguration.systemd.user.services.codex-remote-control.Service.Environment or [ ])
  == [ ];
assert remoteControlService.Service.WorkingDirectory == "/home/codex-remote-control-test/primary";
assert
  secondConfiguration.systemd.user.services.codex-remote-control.Service.WorkingDirectory
  == "/home/codex-remote-control-second/primary";
assert builtins.length remoteControlService.Service.ExecStart == 1;
pkgs.runCommand "codex-remote-control-contract" { inherit activationPackage; } ''
  set -eu
  test "${builtins.head remoteControlService.Service.ExecStart}" = "${codexCliPackage}/bin/codex app-server --remote-control --listen unix://"
  test -f "$activationPackage/home-files/.config/systemd/user/codex-remote-control.service"
  grep -F 'codex app-server --remote-control --listen unix://' \
    "$activationPackage/home-files/.config/systemd/user/codex-remote-control.service"
  ! grep -R -F 'agent-intercom' "$activationPackage"
  touch "$out"
''
