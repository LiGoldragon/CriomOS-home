{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  enabled = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size "Min";
  package = pkgs.callPackage ../../../../owned-agents/codex-next { };
  nextHome = "${config.home.homeDirectory}/.codex-next";
  socket = "${nextHome}/app-server-control/app-server-control.sock";
  recoveryUnit = "codex-remote-control-next-recovery.service";
  prepare = pkgs.writeShellScript "codex-next-prepare" ''
    set -eu
    umask 077
    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg nextHome}
    ${pkgs.coreutils}/bin/chmod 700 ${lib.escapeShellArg nextHome}
    # Bootstrap account data once; never share the mutable session database.
    for file in auth.json config.toml; do
      if [ ! -e ${lib.escapeShellArg nextHome}/"$file" ] && [ -f ${lib.escapeShellArg config.home.homeDirectory}/.codex/"$file" ]; then
        ${pkgs.coreutils}/bin/install -m600 ${lib.escapeShellArg config.home.homeDirectory}/.codex/"$file" ${lib.escapeShellArg nextHome}/"$file"
      fi
    done
  '';
  client = pkgs.writeShellApplication {
    name = "codex-next";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg nextHome}
      exec ${package}/bin/codex --remote ${lib.escapeShellArg "unix://${socket}"} "$@"
    '';
  };
  flowClient = pkgs.writeShellApplication {
    name = "codex-next-flow-client";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg nextHome}
      exec ${package}/bin/codex "$@"
    '';
  };
in
{
  options.criomosHome.codexNext = {
    rawClientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Raw immutable next Codex package without endpoint selection.";
    };
    clientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = flowClient;
      description = "Immutable Flow client wrapper that sets only the isolated next CODEX_HOME and forwards argv unchanged.";
    };
    remoteClientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = client;
      description = "Administrative next client wrapper with the next remote endpoint preselected.";
    };
  };

  config = lib.mkIf enabled {
    home.packages = [ client ];
    systemd.user.services.codex-remote-control-next = {
      # The declared server is the single systemd owner of the next endpoint.
      # A transient `codex-remote-control-next-recovery.service` (systemd-run)
      # listening on the same socket is stopped before this unit starts,
      # and a socket still held by anything else ends in a bounded `failed`
      # state instead of an unbounded restart loop.
      Unit = {
        Description = "Codex Remote Control next server";
        Conflicts = [ recoveryUnit ];
        After = [ recoveryUnit ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };
      Service = {
        WorkingDirectory = "${config.home.homeDirectory}/primary";
        Environment = [ "CODEX_HOME=${nextHome}" ];
        ExecStartPre = "${prepare}";
        ExecStart = "${package}/bin/codex app-server --remote-control --listen unix://${socket}";
        UMask = "0077";
        LimitNOFILE = 524288;
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
