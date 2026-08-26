{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
  codexTuiFixtureCli = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      printf '%s\n' "$@"
    '';
  };
  codexTuiFixture = pkgs.callPackage ../../packages/codex/tui.nix {
    codexCliPackage = codexTuiFixtureCli;
  };
  codexRemoteControlModule = ../../modules/home/profiles/min/agent-intercom.nix;
  mkConfiguration =
    user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = {
          node.services = [ ];
          users.${user.name} = user;
        };
      };
      modules = [
        codexRemoteControlModule
        {
          home = {
            username = "codex-remote-control-test";
            homeDirectory = "/home/codex-remote-control-test";
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
  configuration = mkConfiguration codexUser;
  nonCodexConfiguration = mkConfiguration nonCodexUser;
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
          sharedModules = [ codexRemoteControlModule ];
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
assert embeddedConfiguration.config.home-manager.users.${embeddedUserName}.systemd.user.services ? codex-remote-control;
assert remoteControlService.Service.UMask == "0077";
assert remoteControlService.Service.Restart == "always";
assert builtins.length remoteControlService.Service.ExecStart == 1;
pkgs.runCommand "codex-remote-control-contract" { }
  ''
    set -eu

    expect_remote() {
      test "$("${codexTuiFixture}/bin/codex" "$@")" = "$(printf '%s\n' --remote unix:// "$@")"
    }
    expect_raw() {
      test "$("${codexTuiFixture}/bin/codex" "$@")" = "$(printf '%s\n' "$@")"
    }
    expect_remote "fresh prompt"
    expect_remote --profile mobile --model gpt-5.6-terra "fresh prompt"
    expect_remote --ask-for-approval never --sandbox workspace-write "fresh prompt"
    expect_remote -c 'model="gpt-5.6-terra"' resume thread-id
    expect_remote fork thread-id
    expect_remote agents
    expect_raw --version
    expect_raw -V
    expect_raw --help
    expect_raw -h
    expect_raw help
    expect_raw resume --help
    expect_raw exec "one-shot task"
    expect_raw app-server proxy
    expect_raw login
    expect_raw --remote unix:///tmp/other.sock resume thread-id
    expect_raw resume --remote unix:///tmp/other.sock thread-id
    expect_raw agents --remote unix:///tmp/other.sock
    expect_remote -- --remote
    expect_remote -- --version
    touch "$out"
  ''
