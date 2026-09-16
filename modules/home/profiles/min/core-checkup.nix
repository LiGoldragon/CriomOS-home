{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) attrs bool listOf path str;
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
    rosterFile = mkOption { type = path; default = /etc/core-checkup/roster.json; description = "Immutable OS-owned roster artifact; Home treats it as opaque input."; };
    policyFile = mkOption { type = str; readOnly = true; default = "${config.xdg.configHome}/core-checkup/policy.json"; description = "Home-generated generic policy file."; };
    codexTargets = mkOption { type = listOf attrs; default = [ ]; description = "Explicit fresh Codex harness targets supplied by the owning deployment."; };
    claudeTargets = mkOption { type = listOf attrs; default = [ ]; description = "Explicit fresh Claude harness targets supplied by the owning deployment."; };
    sourceRevision = mkOption { type = str; readOnly = true; default = "fbdc399f2a8ae94c80f0e8afaac9392836e3a2a2"; description = "Pinned primary source revision carried by inputs.core-checkup-source."; };
  };

  config = mkIf cfg.enable {
    home.packages = [ runner ];
    xdg.configFile."core-checkup/policy.json".text = builtins.toJSON {
      eventLog.retention = "operator-managed; no automatic deletion";
      allowRepair = false;
      wake.enabled = false;
      luna = true;
      quotaProbe.socketPath = "$HOME/.codex/app-server-control/app-server-control.sock";
      units = [ ];
      harness = {
        codexTargets = cfg.codexTargets;
        claudeTargets = cfg.claudeTargets;
      };
    };
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
        ExecStartPre = "${pkgs.coreutils}/bin/test -r ${cfg.rosterFile}";
        ExecStart = "${runner}/bin/core-checkup ${cfg.rosterFile} ${cfg.policyFile} %S/core-checkup/events.ndjson %S/core-checkup/state.json";
      };
    };
    systemd.user.timers.core-checkup = {
      Unit.Description = "Run core checkup every 30 minutes";
      Timer = { OnBootSec = "5m"; OnUnitActiveSec = "30min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
