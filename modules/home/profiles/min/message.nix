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
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;

  system = pkgs.stdenv.hostPlatform.system;
  messagePackage = inputs.message.packages.${system}.default;

  messageProfilePackage =
    pkgs.runCommand "${messagePackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        for binary in ${messagePackage}/bin/*; do
          ln -s "$binary" "$out/bin/$(basename "$binary")"
        done
        rm $out/bin/message $out/bin/message-meta $out/bin/meta-message
        makeWrapper ${messagePackage}/bin/message $out/bin/message \
          --run 'export MESSAGE_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/message/message.sock"'
        makeWrapper ${messagePackage}/bin/message-meta $out/bin/message-meta \
          --run 'export MESSAGE_META_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/message/message-owner.sock"'
        ln -s message-meta $out/bin/meta-message
      '';

  # The message daemon is the messenger: the stateful local messaging
  # component owning the durable agent-identity map and delivery registry
  # in `messenger-v6.sema`. Runtime layout mirrors orchestrate: the sema store
  # and binary daemon configuration live under XDG state, sockets under the user
  # runtime directory so stale endpoints disappear with the login session.
  stateDirectory = "${config.xdg.stateHome}/message";
  configurationPath = "${stateDirectory}/message-daemon.rkyv";
  databasePath = "${stateDirectory}/messenger-v6.sema";
  runtimeDirectory = "%t/message";
  workingSocketPath = "${runtimeDirectory}/message.sock";
  metaSocketPath = "${runtimeDirectory}/message-owner.sock";
  ownerLabel = "message";
  # No router daemon is deployed. These router and empty-ingress coordinates
  # preserve both the previously published Home configuration and the current
  # configuration archive observed before adoption. The owner is the projected
  # Home user: systemd runs this user unit as that uid. The stable `message`
  # owner label is also preserved from the observed current archive.
  #
  # This names the canonical location the
  # co-resident router's working socket will occupy when one exists; the
  # messenger connects to it lazily per forward, so an absent router only
  # degrades host-to-host forwards to a typed unreachable outcome, never
  # startup or local registry work.
  routerSocketPath = "%t/router/router.sock";

  # message-write-configuration takes one inline brace object (the
  # single-argument text edge). Its producer-owned contract is a nested
  # nested socket/owner object, followed by the store path, label,
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
      "{ { $working_socket 384 $meta_socket 384 $router_socket [] UnixUser.$(${pkgs.coreutils}/bin/id -u) } ${databasePath} ${ownerLabel} ${configurationPath} }"
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

  config = mkIf (sizeAtLeast "Min" && config.criomosHome.message.enable) {
    home.packages = [ messageProfilePackage ];

    systemd.user.services.message-daemon = {
      Unit = {
        Description = "Message (messenger) local messaging daemon";
        After = [ "flow-nexus.service" ];
        Requires = [ "flow-nexus.service" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        RuntimeDirectory = "message";
        RuntimeDirectoryMode = "0700";
        Environment = [ "FLOW_SOCKET=%t/flow/flow.sock" ];
        ExecStartPre = "${writeConfigurationScript} ${workingSocketPath} ${metaSocketPath} ${routerSocketPath}";
        ExecStart = "${messagePackage}/bin/message-nexus ${configurationPath}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
