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
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;
  service = moduleConfiguration.systemd.user.services.message-daemon.Service;
  writer = service.ExecStartPre;
in
assert service.ExecStart == "${messagePackage}/bin/message-daemon ${signalPath}";
assert service.RuntimeDirectory == "message";
assert service.RuntimeDirectoryMode == "0700";
pkgs.runCommand "message-service-path" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  set -eu

  grep -F 'ConfigurationWriteRequest.{' ${writer}
  ! grep -F '(ConfigurationWriteRequest ' ${writer}
  grep -F '${messagePackage}/bin/message-write-configuration' ${writer}
  touch "$out"
''
