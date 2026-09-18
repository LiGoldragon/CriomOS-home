{ inputs, pkgs, ... }:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  messageModule = ../../modules/home/profiles/min/message.nix;

  homeDirectory = "/build/message-service-home";
  stateHome = "${homeDirectory}/.local/state";
  stateDirectory = "${stateHome}/message";
  configurationPath = "${stateDirectory}/message-daemon.rkyv";
  databasePath = "${stateDirectory}/messenger-v6.sema";
  messagePackage = inputs.message.packages.${system}.default;
  messageConfigurationContract =
    inputs.message.checks.${system}.message-startup-request-writes-a-loadable-configuration;

  moduleResult = import messageModule {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      home.username = "message-test-user";
      xdg.stateHome = stateHome;
      criomosHome.message.enable = true;
    };
    user.size = "Min";
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;
  unit = moduleConfiguration.systemd.user.services.message-daemon;
  service = unit.Service;
  writerCommand = lib.head (lib.splitString " " service.ExecStartPre);
in
assert unit.Unit.After == [ "flow-nexus.service" ];
assert unit.Unit.Requires == [ "flow-nexus.service" ];
assert service.ExecStart == "${messagePackage}/bin/message-nexus ${configurationPath}";
assert service.RuntimeDirectory == "message";
assert service.RuntimeDirectoryMode == "0700";
assert service.Environment == [ "FLOW_SOCKET=%t/flow/flow.sock" ];
pkgs.runCommand "message-service-path"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.gnugrep
    ];
    inherit messageConfigurationContract;
  }
  ''
    set -eu

    # This dependency is Message's own positive writer/read-back witness. The
    # Home-specific witness below then executes this module's generated writer.
    test -e "$messageConfigurationContract"

    runtime="$PWD/runtime"
    mkdir -p "$runtime"

    writer_receipt="$(${writerCommand} \
      "$runtime/message.sock" \
      "$runtime/message-owner.sock" \
      "$runtime/router.sock")"

    test "$writer_receipt" = '{ ${configurationPath} }'
    test -s '${configurationPath}'
    test ! -e '${databasePath}'

    # Force the daemon to stop after decoding and validating the archive but
    # before it can create or open a Sema store. A directory at the selected
    # database path makes the typed store open fail without state mutation.
    mkdir '${databasePath}'
    if ${messagePackage}/bin/message-nexus '${configurationPath}' \
        >daemon.stdout 2>daemon.stderr; then
      echo 'message-nexus unexpectedly started with a directory as its database' >&2
      exit 1
    fi
    grep -F 'message-daemon: component:' daemon.stderr
    ! grep -F 'message-daemon: configuration:' daemon.stderr
    test -z "$(find '${databasePath}' -mindepth 1 -print -quit)"

    touch "$out"
  ''
