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
  serviceCommand = builtins.concatStringsSep "\n" remoteControlService.Service.ExecStart;
  serviceRunner = pkgs.writeShellScript "codex-remote-control-service" serviceCommand;
in
assert configuration.systemd.user.services ? codex-remote-control;
assert !(nonCodexConfiguration.systemd.user.services ? codex-remote-control);
assert remoteControlService.Service.UMask == "0077";
assert remoteControlService.Service.Restart == "always";
assert builtins.length remoteControlService.Service.ExecStart == 1;
pkgs.runCommand "codex-remote-control-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.inotify-tools
      pkgs.python3
      profile
    ];
  }
  ''
    set -eu

    ${profile}/bin/codex --version >/dev/null
    ${agentIntercomPackage}/bin/codex-raw --version >/dev/null

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
    expect_raw exec "one-shot task"
    expect_raw app-server proxy
    expect_raw login
    expect_raw --remote unix:///tmp/other.sock resume thread-id
    expect_raw resume --remote unix:///tmp/other.sock thread-id
    expect_raw agents --remote unix:///tmp/other.sock
    expect_remote -- --remote

    codex_home="$TMPDIR/codex-home"
    control_directory="$codex_home/app-server-control"
    control_socket="$control_directory/app-server-control.sock"
    service_home="$TMPDIR/service-home"
    mkdir -p "$control_directory" "$service_home"

    inotifywait --quiet --timeout 15 --event create --event moved_to "$control_directory" > "$TMPDIR/socket-events" &
    watcher_pid=$!
    HOME="$service_home" CODEX_HOME="$codex_home" ${serviceRunner} > "$TMPDIR/app-server.out" 2> "$TMPDIR/app-server.err" &
    server_pid=$!

    wait "$watcher_pid"
    test -S "$control_socket"
    ${pkgs.python3}/bin/python ${./initialize.py} "$control_socket" "$codex_home"

    kill "$server_pid"
    wait "$server_pid" || true
    touch "$out"
  ''
