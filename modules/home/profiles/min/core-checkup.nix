{ config, lib, pkgs, inputs, ... }:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) attrs bool listOf path str;
  cfg = config.criomosHome.coreCheckup;
  runner = pkgs.writeShellApplication {
    name = "core-checkup";
    runtimeInputs = [ pkgs.nodejs pkgs.iproute2 pkgs.iputils pkgs.systemd pkgs.util-linux config.criomos.corePackages.codex config.criomos.corePackages.claude ];
    text = ''
      exec ${pkgs.nodejs}/bin/node ${inputs.core-checkup-source}/tools/core-checkup.mjs "$@"
    '';
  };
  preflight = pkgs.writeShellApplication {
    name = "core-checkup-preflight";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      roster="$1"
      event_file="$2"
      if test -r "$roster"; then
        exit 0
      fi
      mkdir -p "$(dirname "$event_file")"
      printf '{"schema":"core-checkup/v1","at":"%s","kind":"config","name":"core-checkup","status":"config_missing","reason":"roster_unreadable"}\n' "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)" >> "$event_file"
      exit 1
    '';
  };
  resultReporter = pkgs.writeShellApplication {
    name = "core-checkup-service-result";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      event_file="$1"
      service_result="''${SERVICE_RESULT:-unknown}"
      exit_code="''${EXIT_CODE:-unknown}"
      exit_status="''${EXIT_STATUS:-}"

      case "$service_result" in
        success) exit 0 ;;
        timeout) outcome=global_timeout ;;
        oom-kill) outcome=oom_kill ;;
        exit-code) outcome=service_exit_code ;;
        signal) outcome=service_signal ;;
        core-dump) outcome=service_core_dump ;;
        protocol|watchdog|resources|start-limit-hit) outcome=service_failure ;;
        *) service_result=unknown; outcome=service_failure ;;
      esac
      case "$exit_code" in
        exited|killed|dumped) ;;
        *) exit_code=unknown ;;
      esac
      case "$exit_status" in
        0|[1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
        *) exit_status=null ;;
      esac
      mkdir -p "$(dirname "$event_file")"
      printf '{"schema":"core-checkup/v1","at":"%s","kind":"service-result","name":"core-checkup","status":"%s","service_result":"%s","exit_code":"%s","exit_status":%s}\n' \
        "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)" "$outcome" "$service_result" "$exit_code" "$exit_status" >> "$event_file"
    '';
  };
in {
  options.criomosHome.coreCheckup = {
    enable = mkOption { type = bool; default = false; description = "Install the generic, OS-projected core-checkup user timer."; };
    rosterFile = mkOption { type = path; default = /etc/core-checkup/roster.json; description = "Immutable OS-owned roster artifact; Home treats it as opaque input."; };
    policyFile = mkOption { type = str; readOnly = true; default = "${config.xdg.configHome}/core-checkup/policy.json"; description = "Home-generated generic policy file."; };
    codexTargets = mkOption { type = listOf attrs; default = [ ]; description = "Explicit fresh Codex harness targets supplied by the owning deployment."; };
    claudeTargets = mkOption { type = listOf attrs; default = [ ]; description = "Explicit fresh Claude harness targets supplied by the owning deployment."; };
    sourceRevision = mkOption { type = str; readOnly = true; default = "37ed03c74787f4a5e825895140cc64879e41ed4a"; description = "Pinned primary source revision carried by inputs.core-checkup-source."; };
  };

  config = mkIf cfg.enable {
    home.packages = [ runner ];
    xdg.configFile."core-checkup/policy.json".text = builtins.toJSON {
      eventLog.retention = "operator-managed; no automatic deletion";
      allowRepair = false;
      wake.enabled = false;
      # This monitor has no model child. A future judgment job is a distinct
      # surface, so a model request is rejected by the runner rather than
      # treated as a sandbox or working-directory policy.
      luna = false;
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
        StateDirectoryMode = "0700";
        RuntimeDirectory = "core-checkup";
        WorkingDirectory = "%t/core-checkup";
        TimeoutStartSec = "180s";
        KillMode = "control-group";
        MemoryMax = "256M";
        NoNewPrivileges = true;
        Environment = "PATH=${lib.makeBinPath [ pkgs.nodejs pkgs.iproute2 pkgs.iputils pkgs.systemd pkgs.util-linux config.criomos.corePackages.codex config.criomos.corePackages.claude ]}";
        ExecStartPre = "${preflight}/bin/core-checkup-preflight ${cfg.rosterFile} %S/core-checkup/events.ndjson";
        ExecStart = "${runner}/bin/core-checkup ${cfg.rosterFile} ${cfg.policyFile} %S/core-checkup/events.ndjson %S/core-checkup/state.json";
        # ExecStopPost also runs when ExecStartPre fails. It maps only
        # systemd's bounded result enums, so timeout or OOM is never
        # mislabeled as a runner or roster failure.
        ExecStopPost = "${resultReporter}/bin/core-checkup-service-result %S/core-checkup/events.ndjson";
      };
    };
    systemd.user.timers.core-checkup = {
      Unit.Description = "Run core checkup every 30 minutes";
      Timer = { OnBootSec = "5m"; OnUnitActiveSec = "30min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
