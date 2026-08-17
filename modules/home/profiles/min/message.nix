{
  config,
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  messagePackage = inputs.message.packages.${system}.default;

  messageProfilePackage =
    pkgs.runCommand "${messagePackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        for binary in ${messagePackage}/bin/*; do
          ln -s "$binary" "$out/bin/$(basename "$binary")"
        done
        rm $out/bin/message $out/bin/meta-message
        makeWrapper ${messagePackage}/bin/message $out/bin/message \
          --run 'export MESSAGE_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/message/message.sock"'
        makeWrapper ${messagePackage}/bin/meta-message $out/bin/meta-message \
          --run 'export MESSAGE_META_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/message/message-owner.sock"'
      '';

  # The message daemon is the messenger: the stateful local messaging
  # component owning the durable agent-identity map and delivery registry
  # in `messenger.sema`. Runtime layout mirrors orchestrate: the sema store
  # and binary daemon signal live under XDG state, sockets under the user
  # runtime directory so stale endpoints disappear with the login session.
  stateDirectory = "${config.xdg.stateHome}/message";
  signalPath = "${stateDirectory}/message-daemon.signal";
  databasePath = "${stateDirectory}/messenger.sema";
  runtimeDirectory = "%t/message";
  workingSocketPath = "${runtimeDirectory}/message.sock";
  metaSocketPath = "${runtimeDirectory}/message-owner.sock";
  # No router daemon is deployed. This names the canonical location the
  # co-resident router's working socket will occupy when one exists; the
  # messenger connects to it lazily per forward, so an absent router only
  # degrades host-to-host forwards to a typed unreachable outcome, never
  # startup or local registry work.
  routerSocketPath = "%t/router/router.sock";

  # message-write-configuration takes one inline brace object (the
  # single-argument text edge). Its producer-owned contract is a nested
  # parenthesized socket/owner object, followed by the store path, label,
  # and output path. The owner uid is read at service start so the unit does
  # not bake a numeric uid into the store; systemd expands the %t-derived
  # socket arguments before the script runs.
  writeConfigurationScript = pkgs.writeShellScript "message-write-configuration-request" ''
    set -eu
    working_socket="$1"
    meta_socket="$2"
    router_socket="$3"
    ${pkgs.coreutils}/bin/mkdir -p ${stateDirectory}
    exec ${messagePackage}/bin/message-write-configuration \
      "{($working_socket 432 $meta_socket 384 $router_socket [] UnixUser.$(${pkgs.coreutils}/bin/id -u)) ${databasePath} ${config.home.username} ${signalPath}}"
  '';
in
{
  options.criomosHome.message = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Supervise the message (messenger) daemon as a systemd --user service.";
    };
  };

  config = mkIf (size.min && config.criomosHome.message.enable) {
    home.packages = [ messageProfilePackage ];

    systemd.user.services.message-daemon = {
      Unit = {
        Description = "Message (messenger) local messaging daemon";
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        RuntimeDirectory = "message";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = "${writeConfigurationScript} ${workingSocketPath} ${metaSocketPath} ${routerSocketPath}";
        ExecStart = "${messagePackage}/bin/message-daemon ${signalPath}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
