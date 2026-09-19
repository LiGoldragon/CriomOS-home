{ config, lib, pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runner = pkgs.writeShellApplication {
    name = "field-luna-heartbeat";
    runtimeInputs = [ pkgs.nodejs pkgs.python3 pkgs.systemd inputs.herdr.packages.${system}.herdr inputs.orchestrate.packages.${system}.default config.criomos.corePackages.codex ];
    text = ''
      exec ${pkgs.nodejs}/bin/node ${inputs.prompt-relay-source}/tools/field-luna-heartbeat.mjs "$@"
    '';
  };
in {
  systemd.user.services.field-luna-heartbeat = {
    Unit.Description = "Bounded Field Luna retirement and archive maintenance";
    Service = {
      Type = "oneshot";
      StateDirectory = "field-luna-heartbeat";
      StateDirectoryMode = "0700";
      RuntimeMaxSec = "120s";
      TimeoutStartSec = "120s";
      MemoryMax = "256M";
      NoNewPrivileges = true;
      ExecStart = "${runner}/bin/field-luna-heartbeat %S/field-luna-heartbeat ${inputs.prompt-relay-source}";
    };
  };
  systemd.user.timers.field-luna-heartbeat = {
    Unit.Description = "Run Field Luna maintenance every 30 minutes";
    Timer = { OnBootSec = "5m"; OnUnitActiveSec = "30min"; Persistent = true; };
    Install.WantedBy = [ "timers.target" ];
  };
  systemd.user.paths.field-luna-heartbeat = {
    Unit.Description = "Run Field Luna maintenance after HM lifecycle changes";
    Path.PathChanged = [ "%h/.local/state/hacky-messenger" "%h/.local/state/hacky-messenger/retired" ];
    Install.WantedBy = [ "default.target" ];
  };
}
