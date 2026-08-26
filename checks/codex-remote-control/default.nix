{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
  agentIntercomPackage = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
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
        inherit inputs user;
        hexis = inputs.hexis.packages.${system}.default;
        horizon.node.services = [ ];
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
  profile = pkgs.buildEnv {
    name = "codex-remote-control-profile";
    paths = configuration.home.packages;
  };
  remoteControlService = configuration.systemd.user.services.codex-remote-control;
in
assert configuration.systemd.user.services ? codex-remote-control;
assert !(nonCodexConfiguration.systemd.user.services ? codex-remote-control);
assert remoteControlService.Service.UMask == "0077";
assert remoteControlService.Service.Restart == "always";
assert builtins.length remoteControlService.Service.ExecStart == 1;
pkgs.runCommand "codex-remote-control-contract"
  {
    nativeBuildInputs = [
      profile
    ];
  }
  ''
    set -eu

    test "$(${profile}/bin/codex --version)" = "codex-cli ${codexCliPackage.version}"
    test "$(${agentIntercomPackage}/bin/codex-raw --version)" = "codex-cli ${codexCliPackage.version}"

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
