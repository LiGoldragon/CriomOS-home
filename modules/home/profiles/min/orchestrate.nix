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
  orchestratePackage = inputs.orchestrate.packages.${system}.default;

  # The orchestrate daemon supervises the multi-agent claim/coordination
  # fabric for the `primary` workspace under this user's home. It was
  # previously started by hand (`setsid nohup orchestrate-daemon <signal>`)
  # with no supervisor, so a crash silently took the whole claim fabric down
  # until a manual restart. This unit gives it `Restart=on-failure` and
  # start-on-login instead.
  #
  # The signal file enumerates the daemon's sockets + redb database and is
  # created out-of-band by the workspace; the daemon reads it on start and
  # unlinks any stale sockets before rebinding. The path is workspace-specific
  # for now (like the prometheus ssh matchBlock in profiles/min/default.nix) —
  # it could be derived once a generic workspace resolver exists.
  signalPath = "${config.home.homeDirectory}/primary/orchestrate/orchestrate-daemon.signal";
in
{
  options.criomosHome.orchestrate = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Supervise the orchestrate multi-agent claim/coordination daemon as a systemd --user service.";
    };
  };

  config = mkIf (size.min && config.criomosHome.orchestrate.enable) {
    systemd.user.services.orchestrate-daemon = {
      Unit = {
        Description = "Orchestrate multi-agent claim/coordination daemon";
        # Bound restart storms: if the signal file or a socket is
        # transiently unavailable the unit backs off instead of spinning.
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        ExecStart = "${orchestratePackage}/bin/orchestrate-daemon ${signalPath}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      # default.target is reached on user login, so the daemon starts on login.
      Install.WantedBy = [ "default.target" ];
    };
  };
}
