{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.criomosHome.coreHeartbeat;
  source = ../../../../packages/core-heartbeat/source;
  configuration = pkgs.writeText "core-heartbeat.json" (builtins.toJSON (cfg.settings // {
    promptRelay = "${inputs.prompt-relay-source}/tools/prompt-relay";
  }));
  runner = pkgs.writeShellApplication {
    name = "core-heartbeat";
    runtimeInputs = [ pkgs.nodejs pkgs.python3 pkgs.jujutsu pkgs.git pkgs.util-linux
      config.criomos.corePackages.codex config.criomos.corePackages.claude ];
    text = ''
      exec node ${source}/tools/heartbeat.mjs "''${1:-${configuration}}"
    '';
  };
in {
  options.criomosHome.coreHeartbeat = {
    enable = lib.mkEnableOption "the bounded, quota-gated cluster heartbeat";
    settings = lib.mkOption {
      type = (pkgs.formats.json {}).type;
      default = {};
      description = "Explicit operator-owned lane, transcript, state and recipient paths.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ runner ];
    xdg.configFile."core-checkup/heartbeat.json".source = configuration;
    systemd.user.services.core-heartbeat = {
      Unit.Description = "Quota-gated cluster heartbeat; no repairs or restarts";
      Service = {
        Type = "oneshot";
        ExecStart = "${runner}/bin/core-heartbeat";
        TimeoutStartSec = "180s";
        MemoryMax = "512M";
        NoNewPrivileges = true;
        UMask = "0077";
      };
    };
    systemd.user.timers.core-heartbeat = {
      Unit.Description = "Poll heartbeat cadence every five minutes";
      Timer = { OnBootSec = "5min"; OnUnitActiveSec = "5min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
