{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool package str;
  cfg = config.criomosHome.coreCheckup;
  runner = pkgs.writeShellApplication {
    name = "core-checkup";
    runtimeInputs = [ pkgs.nodejs pkgs.iputils pkgs.systemd config.criomos.corePackages.codex config.criomos.corePackages.claude ];
    text = ''
      exec ${pkgs.nodejs}/bin/node ${inputs.core-checkup-source}/tools/core-checkup.mjs "$@"
    '';
  };
in {
  options.criomosHome.coreCheckup = {
    enable = mkOption { type = bool; default = false; description = "Install the generic, OS-projected core-checkup user timer."; };
    configPath = mkOption { type = str; default = "/etc/core-checkup/config.json"; description = "OS-projected runtime checkup configuration path."; };
    sourceRevision = mkOption { type = str; readOnly = true; default = "667b9bbed04f62dc55a1e0d25c84b484841bd6f4"; description = "Pinned primary source revision carried by inputs.core-checkup-source."; };
  };

  config = mkIf cfg.enable {
    home.packages = [ runner ];
    systemd.user.services.core-checkup = {
      Unit.Description = "Bounded core checkup from pinned primary source";
      Service = {
        Type = "oneshot";
        StateDirectory = "core-checkup";
        RuntimeMaxSec = "120s";
        TimeoutStartSec = "120s";
        MemoryMax = "256M";
        NoNewPrivileges = true;
        Environment = "PATH=${lib.makeBinPath [ pkgs.nodejs pkgs.iputils pkgs.systemd config.criomos.corePackages.codex config.criomos.corePackages.claude ]}";
        ExecStart = "${runner}/bin/core-checkup ${cfg.configPath} %S/core-checkup/events.ndjson %S/core-checkup/state.json";
      };
    };
    systemd.user.timers.core-checkup = {
      Unit.Description = "Run core checkup every 30 minutes";
      Timer = { OnBootSec = "5m"; OnUnitActiveSec = "30min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
