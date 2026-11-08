{ inputs, pkgs, ... }:
# The Field monitors evaluate to no services by default and to callable
# services, without schedules, when enabled.
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
      };
    }).config;

  services = on.systemd.user.services;
  timers = on.systemd.user.timers;
  primaryRoot = "${homeDirectory}/primary";
  stateHome = "${homeDirectory}/.local/state";
  configHome = "${homeDirectory}/.config";
  lunaRunner = lib.head (lib.splitString " " (text services.field-luna-research.Service.ExecStart));

  checks = [
    # Default off: no unit of any monitor or hand-made-unit warning.
    {
      ok = lib.all (name: !(off.systemd.user.services ? ${name}) && !(off.systemd.user.timers ? ${name})) monitors;
      msg = "a Field monitor is declared while its enable option is off";
    }
    {
      ok = !(off.home.activation ? fieldMonitoringHandMadeUnits) || off.home.activation.fieldMonitoringHandMadeUnits == { };
      msg = "hand-made-unit warning present with every monitor off";
    }
    {
      ok = lib.all (name: services ? ${name} && !(timers ? ${name})) monitors;
      msg = "an enabled monitor is missing its callable service or still has a timer";
    }
    # core-checkup
    {
      ok =
        (text services.core-checkup.Service.StateDirectory) == "core-checkup"
        && (text services.core-checkup.Service.RuntimeMaxSec) == "120s"
        && (text services.core-checkup.Service.MemoryMax) == "256M"
        && hasInfix "${inputs.core-checkup-source}/tools/core-checkup.mjs " (text services.core-checkup.Service.ExecStart)
        && hasSuffix " ${configHome}/core-checkup/policy.json %S/core-checkup/events.ndjson %S/core-checkup/state.json" (text services.core-checkup.Service.ExecStart);
      msg = "core-checkup callable service contents differ";
    }
    # field-census
    {
      ok =
        (text services.field-census.Service.ExecStart) == "${pkgs.nodejs}/bin/node ${inputs.field-monitoring-source}/tools/field-census-cycle.mjs --observe-only"
        && (text services.field-census.Service.WorkingDirectory) == primaryRoot
        && has "FIELD_CENSUS_STATE=${stateHome}/field-census" services.field-census.Service.Environment
        && has "FIELD_CENSUS_CONFIG=${configHome}/field-census/recipients.json" services.field-census.Service.Environment
        && (text services.field-census.Service.UMask) == "0077";
      msg = "field-census callable service contents differ";
    }
    # field-checkup-shadow
    {
      ok =
        (text services.field-checkup-shadow.Service.ExecStart) == "${pkgs.nodejs}/bin/node ${inputs.field-monitoring-source}/tools/field-checkup-shadow-cycle.mjs"
        && (text services.field-checkup-shadow.Unit.After) == "field-census.service"
        && has "FIELD_CHECKUP_ROSTER=${configHome}/field-checkup-shadow/roster.json" services.field-checkup-shadow.Service.Environment;
      msg = "field-checkup-shadow callable service contents differ";
    }
    # field-luna-research
    {
      ok =
        hasSuffix "/bin/field-luna-research-run --once" (text services.field-luna-research.Service.ExecStart)
        && (text services.field-luna-research.Service.Environment) == "FIELD_PRIMARY_ROOT=${primaryRoot}"
        && (text services.field-luna-research.Service.TimeoutStartSec) == "610";
      msg = "field-luna-research callable service contents differ";
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
    # The Luna runner keeps the flock guard and runs the pinned script.
    grep -q "flock -n 9" ${lunaRunner}
    grep -q "${inputs.field-luna-research-source}/bin/field-luna-research.mjs" ${lunaRunner}
    touch $out
  ''
