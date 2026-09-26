{ inputs, pkgs, ... }:

let
  # The module reaches for `lib.hm.dag.entryAfter`; the stub keeps the
  # activation entry's script reachable without a whole home-manager
  # evaluation.
  lib = pkgs.lib // {
    hm.dag.entryAfter = _dependencies: data: { inherit data; };
  };
  system = pkgs.stdenv.hostPlatform.system;
  messageModule = ../../modules/home/profiles/min/message.nix;

  homeDirectory = "/build/message-service-home";
  stateHome = "${homeDirectory}/.local/state";
  stateDirectory = "${stateHome}/message";
  retiredDirectory = "${stateDirectory}/retired-0.14";
  messagePackage = inputs.message.packages.${system}.default;
  nexusExecutable = "${messagePackage}/bin/message-nexus";

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
  service = moduleConfiguration.systemd.user.services.message-nexus.Service;
  # `run <script>` is what the activation entry holds; the script is what the
  # test exercises.
  retireScript = lib.elemAt (lib.splitString " " (
    lib.replaceStrings [ "\n" ] [ " " ] moduleConfiguration.home.activation.retireMessengerStore.data
  )) 1;
in
# The Nexus starts with no arguments: 0.16.0 refuses any argument vector but
# `--version`, so an ExecStart carrying a signal path would not start at all.
assert service.ExecStart == nexusExecutable;
assert service.Type == "simple";
assert service.RuntimeDirectory == "message";
assert service.RuntimeDirectoryMode == "0700";
assert !(moduleConfiguration.systemd.user.services ? message-daemon);
# Flow admits exactly the executable this unit runs.
assert moduleConfiguration.criomosHome.flow.messageNexusPath == nexusExecutable;
pkgs.runCommand "message-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.diffutils
    ];
  }
  ''
    set -eu

    # The 0.16.0 command surface: one Nexus and two clients, and none of the
    # executables 0.15.0 retired.
    for binary in message-nexus message message-meta; do
      test -x ${messagePackage}/bin/"$binary"
    done
    for retired in message-daemon meta-message relay message-cluster \
      message-validate-output message-write-configuration; do
      if [ -e ${messagePackage}/bin/"$retired" ]; then
        echo "Message 0.16.0 still ships the retired $retired" >&2
        exit 1
      fi
    done
    ${nexusExecutable} --version | grep -Fx 0.16.0
    if ${nexusExecutable} ${lib.escapeShellArg "${stateDirectory}/message-daemon.signal"}; then
      echo 'message-nexus accepted an argument' >&2
      exit 1
    fi

    # The retirement step moves the 0.14 store and its sidecars aside.
    mkdir -p '${stateDirectory}'
    printf 'live-messenger-ledger\n' > '${stateDirectory}/messenger.sema'
    printf 'preopen-snapshot\n' > '${stateDirectory}/messenger.sema.message-0.14.0.preopen'
    printf 'signal\n' > '${stateDirectory}/message-daemon.signal'
    ${retireScript}
    test ! -e '${stateDirectory}/messenger.sema'
    test ! -e '${stateDirectory}/messenger.sema.message-0.14.0.preopen'
    test ! -e '${stateDirectory}/message-daemon.signal'
    printf 'live-messenger-ledger\n' | cmp - '${retiredDirectory}/messenger.sema'
    printf 'preopen-snapshot\n' | cmp - '${retiredDirectory}/messenger.sema.message-0.14.0.preopen'
    printf 'signal\n' | cmp - '${retiredDirectory}/message-daemon.signal'

    # Idempotent: with the 0.14 state already aside, a second activation does
    # nothing and changes nothing.
    ${retireScript}
    printf 'live-messenger-ledger\n' | cmp - '${retiredDirectory}/messenger.sema'

    # A retired ledger is never overwritten. With both a live store and a
    # differing snapshot present the step refuses and keeps both.
    printf 'second-generation-ledger\n' > '${stateDirectory}/messenger.sema'
    if ${retireScript}; then
      echo 'the retirement step overwrote an existing snapshot' >&2
      exit 1
    fi
    printf 'second-generation-ledger\n' | cmp - '${stateDirectory}/messenger.sema'
    printf 'live-messenger-ledger\n' | cmp - '${retiredDirectory}/messenger.sema'

    touch "$out"
  ''
