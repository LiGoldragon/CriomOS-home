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
  writer = service.ExecStartPre;
  writerExecutable = lib.head (lib.splitString " " writer);
in
assert service.ExecStart == "${messagePackage}/bin/message-daemon ${signalPath}";
assert service.RuntimeDirectory == "message";
assert service.RuntimeDirectoryMode == "0700";
pkgs.runCommand "message-service-path" { nativeBuildInputs = [ pkgs.gnugrep pkgs.coreutils ]; } ''
  set -eu

  # Exercise the exact packaged writer script, through the current Message
  # package rather than a fake executable. This catches a producer Datom-shape
  # change that a source grep cannot see, and proves that the generated
  # request creates a binary configuration at the path the daemon consumes.
  runtime="$TMPDIR/message-runtime"
  mkdir -p "$runtime"
  ${writerExecutable} "$runtime/message.sock" "$runtime/message-owner.sock" "$runtime/router.sock"
  test -s "${signalPath}"
  touch "$out"
''
