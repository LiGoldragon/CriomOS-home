{ inputs, pkgs, ... }:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  messageModule = ../../modules/home/profiles/min/message.nix;

  homeDirectory = "/build/message-service-home";
  stateHome = "${homeDirectory}/.local/state";
  stateDirectory = "${stateHome}/message";
  signalPath = "${stateDirectory}/message-daemon.signal";
  messagePackage = inputs.message.packages.${system}.default;

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
  service = moduleConfiguration.systemd.user.services.message-daemon.Service;
  preserver = lib.head service.ExecStartPre;
  instrumentedPreserver = pkgs.writeShellScript "message-preserve-live-store-race-fixture" (
    lib.replaceStrings
      [ "${pkgs.coreutils}/bin/ln --" ]
      [ "${pkgs.coreutils}/bin/sleep 1\n${pkgs.coreutils}/bin/ln --" ]
      (builtins.readFile preserver)
  );
  writer = lib.last service.ExecStartPre;
  writerScript = lib.head (lib.splitString " " writer);
  preservePath = "${stateDirectory}/messenger.sema.${messagePackage.name}.preopen";
  nexusModuleResult = import messageModule {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      home.username = "message-test-user";
      xdg.stateHome = stateHome;
      criomosHome.message = {
        enable = true;
        daemonBinary = "message-nexus";
      };
    };
    user.size = "Min";
  };
  nexusModuleConfiguration =
    if nexusModuleResult.config ? content then
      nexusModuleResult.config.content
    else
      nexusModuleResult.config;
in
assert service.ExecStart == "${messagePackage}/bin/message-daemon ${signalPath}";
assert
  nexusModuleConfiguration.systemd.user.services.message-daemon.Service.ExecStart
  == "${messagePackage}/bin/message-nexus ${signalPath}";
assert service.RuntimeDirectory == "message";
assert service.RuntimeDirectoryMode == "0700";
pkgs.runCommand "message-service-path" { nativeBuildInputs = [ pkgs.coreutils pkgs.diffutils pkgs.findutils pkgs.gnugrep ]; } ''
  set -eu

  grep -F '"{{$working_socket 432 $meta_socket 384 $router_socket [] UnixUser.$(' ${writerScript}
  ! grep -F '"{($working_socket 432 $meta_socket 384 $router_socket [] UnixUser.$(' ${writerScript}
  ! grep -F '(ConfigurationWriteRequest ' ${writerScript}
  ! grep -F 'ConfigurationWriteRequest.' ${writerScript}
  grep -F '${messagePackage}/bin/message-write-configuration' ${writerScript}

  mkdir -p '${stateDirectory}'
  printf 'live-messenger-before-open\n' > '${stateDirectory}/messenger.sema'
  ${preserver}
  cmp '${stateDirectory}/messenger.sema' '${preservePath}'

  # A partial or mismatched prior snapshot cannot be silently accepted.
  rm '${preservePath}'
  printf 'partial-copy\n' > '${preservePath}'
  if ${preserver}; then
    echo 'Message preserver accepted a mismatched pre-open snapshot' >&2
    exit 1
  fi
  printf 'partial-copy\n' | cmp - '${preservePath}'

  # Simulate an interrupted competing publication after this invocation made
  # its private temporary copy. The final sidecar must remain unpromoted and
  # the invocation must remove its own temporary file through the EXIT trap.
  rm '${preservePath}'
  (
    for _ in $(${pkgs.coreutils}/bin/seq 1 1000); do
      if ${pkgs.findutils}/bin/find '${stateDirectory}' -maxdepth 1 -name '.${messagePackage.name}.preopen.*' -print -quit | ${pkgs.gnugrep}/bin/grep -q .; then
        printf 'competing-partial\n' > '${preservePath}'
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.01
    done
    echo 'Message preserver did not create its temporary snapshot' >&2
    exit 1
  ) &
  competitor=$!
  if ${instrumentedPreserver}; then
    echo 'Message preserver accepted a competing partial snapshot' >&2
    exit 1
  fi
  wait "$competitor"
  printf 'competing-partial\n' | cmp - '${preservePath}'
  if ${pkgs.findutils}/bin/find '${stateDirectory}' -maxdepth 1 -name '.${messagePackage.name}.preopen.*' -print -quit | ${pkgs.gnugrep}/bin/grep -q .; then
    echo 'Message preserver left its interrupted temporary snapshot behind' >&2
    exit 1
  fi
  printf 'live-messenger-before-open\n' | cmp - '${stateDirectory}/messenger.sema'

  # Exercise the same packaged writer that ExecStartPre invokes. A successful
  # write proves the module's nested contract is a Datom Struct at the real
  # package boundary rather than only matching an expected source string.
  ${writerScript} \
    /run/user/1000/message/message.sock \
    /run/user/1000/message/message-owner.sock \
    /run/user/1000/router/router.sock
  test -s '${signalPath}'

  # The exact old nested Meaning must remain a loud refusal.
  if ${messagePackage}/bin/message-write-configuration \
    '{(/run/user/1000/message/message.sock 432 /run/user/1000/message/message-owner.sock 384 /run/user/1000/router/router.sock [] UnixUser.1000) /build/retired-messenger.sema message-test-user /build/retired-message-daemon.signal}'
  then
    echo 'retired parenthesized Message configuration unexpectedly succeeded' >&2
    exit 1
  fi
  touch "$out"
''
