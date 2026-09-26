{ inputs, pkgs, ... }:
# The Field monitors evaluate to no units by default, and to the observed unit
# contents (with pinned scripts) when each is enabled.
let
  inherit (pkgs) lib;
  # Regex-based string predicates refuse store-path context; compare text only.
  plain = builtins.unsafeDiscardStringContext;
  hasInfix = infix: text: lib.hasInfix (plain infix) (plain text);
  hasSuffix = suffix: text: lib.hasSuffix (plain suffix) (plain text);
  # Home Manager stores unit values as lists; read single values as text.
  text = value: if builtins.isList value then lib.concatStringsSep " " (map toString value) else toString value;
  has = entry: value: lib.elem entry (lib.toList value);
  homeDirectory = "/home/field-monitoring-check";
  mkHome =
    extraModule:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        user = {
          size = "Min";
          useColemak = false;
          hasPublicKey = false;
          gitSigningKey = "";
          matrixId = "";
          isMultimediaDev = false;
          emailAddress = "field-monitoring-check@example.invalid";
          githubId = "field-monitoring-check";
          name = "field-monitoring-check";
          publicKeys = [ ];
        };
        horizon.node = {
          name = "field-monitoring-check";
          machine.architecture = "x86_64";
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
        rustToolchain = pkgs.rustc;
      };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/default.nix
        ../../modules/home/profiles/min/field-monitoring.nix
        {
          home = {
            username = "field-monitoring-check";
            inherit homeDirectory;
            stateVersion = "26.11";
          };
        }
        extraModule
      ];
    };

  monitors = [
    "core-checkup"
    "field-census"
    "field-checkup-shadow"
    "field-luna-research"
    "field-monitor-98eb43"
  ];

  off = (mkHome { }).config;
  on =
    (mkHome {
      criomosHome.fieldMonitoring = {
        coreCheckup = {
          enable = true;
          roster = {
            allowRestart = false;
            endpoints = [ ];
            units = [ ];
          };
        };
        fieldCensus.enable = true;
        fieldCheckupShadow.enable = true;
        fieldLunaResearch.enable = true;
        fieldMonitor98eb43.enable = true;
      };
    }).config;

  services = on.systemd.user.services;
  timers = on.systemd.user.timers;
  primaryRoot = "${homeDirectory}/primary";
  stateHome = "${homeDirectory}/.local/state";
  configHome = "${homeDirectory}/.config";
  census98eb43 = lib.last (lib.splitString " " (text services.field-monitor-98eb43.Service.ExecStart));
  lunaRunner = lib.head (lib.splitString " " (text services.field-luna-research.Service.ExecStart));

  checks = [
    # Default off: no unit of any monitor, no hand-made-unit warning, and no
    # declaration for the dropped agent-intercom-fleet-cleanup.
    {
      ok = lib.all (name: !(off.systemd.user.services ? ${name}) && !(off.systemd.user.timers ? ${name})) monitors;
      msg = "a Field monitor is declared while its enable option is off";
    }
    {
      ok = !(off.home.activation ? fieldMonitoringHandMadeUnits) || off.home.activation.fieldMonitoringHandMadeUnits == { };
      msg = "hand-made-unit warning present with every monitor off";
    }
    {
      ok = !(on.systemd.user.services ? agent-intercom-fleet-cleanup);
      msg = "agent-intercom-fleet-cleanup must not be declared (its script is gone)";
    }
    {
      ok = lib.all (name: services ? ${name} && timers ? ${name} && timers.${name}.Install.WantedBy == [ "timers.target" ]) monitors;
      msg = "an enabled monitor lacks its service or timers.target timer";
    }
    # core-checkup
    {
      ok =
        (text services.core-checkup.Service.StateDirectory) == "core-checkup"
        && (text services.core-checkup.Service.RuntimeMaxSec) == "120s"
        && (text services.core-checkup.Service.MemoryMax) == "256M"
        && hasInfix "${inputs.core-checkup-source}/tools/core-checkup.mjs " (text services.core-checkup.Service.ExecStart)
        && hasSuffix " ${configHome}/core-checkup/policy.json %S/core-checkup/events.ndjson %S/core-checkup/state.json" (text services.core-checkup.Service.ExecStart)
        && (text timers.core-checkup.Timer.OnUnitActiveSec) == "30min"
        && (text timers.core-checkup.Timer.OnBootSec) == "5m";
      msg = "core-checkup unit contents differ from the observed unit";
    }
    # field-census
    {
      ok =
        (text services.field-census.Service.ExecStart) == "${pkgs.nodejs}/bin/node ${inputs.field-monitoring-source}/tools/field-census-cycle.mjs --observe-only"
        && (text services.field-census.Service.WorkingDirectory) == primaryRoot
        && has "FIELD_CENSUS_STATE=${stateHome}/field-census" services.field-census.Service.Environment
        && has "FIELD_CENSUS_CONFIG=${configHome}/field-census/recipients.json" services.field-census.Service.Environment
        && (text services.field-census.Service.UMask) == "0077"
        && (text timers.field-census.Timer.OnUnitActiveSec) == "5min";
      msg = "field-census unit contents differ from the observed unit";
    }
    # field-checkup-shadow
    {
      ok =
        (text services.field-checkup-shadow.Service.ExecStart) == "${pkgs.nodejs}/bin/node ${inputs.field-monitoring-source}/tools/field-checkup-shadow-cycle.mjs"
        && (text services.field-checkup-shadow.Unit.After) == "field-census.service"
        && has "FIELD_CHECKUP_ROSTER=${configHome}/field-checkup-shadow/roster.json" services.field-checkup-shadow.Service.Environment
        && (text timers.field-checkup-shadow.Timer.OnBootSec) == "7min"
        && (text timers.field-checkup-shadow.Timer.OnUnitActiveSec) == "30min";
      msg = "field-checkup-shadow unit contents differ from the observed unit";
    }
    # field-luna-research
    {
      ok =
        hasSuffix "/bin/field-luna-research-run --once" (text services.field-luna-research.Service.ExecStart)
        && (text services.field-luna-research.Service.Environment) == "FIELD_PRIMARY_ROOT=${primaryRoot}"
        && (text services.field-luna-research.Service.TimeoutStartSec) == "610"
        && (text timers.field-luna-research.Timer.Unit) == "field-luna-research.service"
        && (text timers.field-luna-research.Timer.OnUnitActiveSec) == "30m";
      msg = "field-luna-research unit contents differ from the observed unit";
    }
    # field-monitor-98eb43
    {
      ok = (text timers.field-monitor-98eb43.Timer.OnBootSec) == "1min" && (text timers.field-monitor-98eb43.Timer.OnUnitActiveSec) == "5min";
      msg = "field-monitor-98eb43 timer differs from the observed timer";
    }
    {
      ok = on.home.activation ? fieldMonitoringHandMadeUnits && hasInfix "field-census.timer" on.home.activation.fieldMonitoringHandMadeUnits.data;
      msg = "hand-made-unit warning missing while monitors are enabled";
    }
  ];
  failures = lib.filter (check: !check.ok) checks;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (check: check.msg) failures)
else
  pkgs.runCommand "field-monitoring" { } ''
    set -eu
    # The pinned sources carry every script the units run.
    test -f ${inputs.core-checkup-source}/tools/core-checkup.mjs
    test -f ${inputs.core-checkup-source}/tools/harness-facts.mjs
    test -f ${inputs.field-monitoring-source}/tools/field-census-cycle.mjs
    test -f ${inputs.field-monitoring-source}/tools/field-census.mjs
    test -f ${inputs.field-monitoring-source}/tools/field-checkup-shadow-cycle.mjs
    test -f ${inputs.field-monitoring-source}/tools/field-structure.mjs
    test -f ${inputs.field-luna-research-source}/bin/field-luna-research.mjs
    # The 98eb43 monitor carries no home-directory tool path after patching.
    ! grep -q "/home/li" ${census98eb43}
    grep -q "const root = '${primaryRoot}';" ${census98eb43}
    grep -q "/bin/hm-send';" ${census98eb43}
    # The Luna runner keeps the flock guard and runs the pinned script.
    grep -q "flock -n 9" ${lunaRunner}
    grep -q "${inputs.field-luna-research-source}/bin/field-luna-research.mjs" ${lunaRunner}
    touch $out
  ''
