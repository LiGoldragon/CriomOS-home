{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.codexHarness;
  plain = config.criomosHome.codexPlain;
  sharedPlain = plain.enable && cfg.hookHome == plain.homeDirectory;
  multiAgentModeHint = "Maximize sub-agents. Run commands, builds, tests, searches and the reading of logs and long files in a sub-agent, and give it every bounded part of your work; keep your own context for judgment and the work only you hold. Reuse a sub-agent that already holds the context before you start a new one. When a kind of work returns, give it a role file.";
  places = config.criomosHome.nexusPlaces;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  system = pkgs.stdenv.hostPlatform.system;
  packages = inputs.codex-harness-nexus.packages.${system};
  nexus = packages.codex-harness-nexus;
  translator = packages.codex-harness-translator;
  nexusUnit = "codex-harness-nexus-040";
  translatorUnit = "codex-harness-translator-040";
  runtime = "%t/nexus/${cfg.place}";
  state = "%S/nexus/${cfg.place}";
  place = lib.escapeShellArg "{ «${cfg.place}» «${runtime}» «${state}» }";
  deployment = ../../../../lib/codex-harness-deployment;
  readiness = "${pkgs.python3}/bin/python3 ${deployment}/socket-readiness.py";
  marker = ".local/bin/codex-harness-report";
  markerPath = "${config.home.homeDirectory}/${marker}";
  readyFile = "codex-harness-translator.ready";
  socketPaths = names: lib.concatMapStringsSep " " (name: "${runtime}/codex-harness${name}.sock") names;
  nexusSockets = socketPaths [ "" "-meta" ];
  translatorSockets = socketPaths [ "-translator" "-meta-translator" "-hook" "-emission" ];
  configure = pkgs.writeShellScript "configure-codex-harness" ''
    set -eu
    ${readiness} wait "$1/codex-harness-emission.sock"
    ${pkgs.python3}/bin/python3 ${deployment}/subscribe.py ${translator}/bin/codex-harness

    apply() {
      actual="$(${translator}/bin/codex-harness-meta "$1")"
      case "$actual" in
        Configured.*) ;;
        *) echo "Codex Harness configuration was refused." >&2; exit 1 ;;
      esac
    }
    apply 'Configure.RowCount.${toString cfg.rowCount}'
    ${lib.optionalString (cfg.threadDatabase != null) ''
      apply ${lib.escapeShellArg "Configure.ThreadDatabase.«${cfg.threadDatabase}»"}
    ''}
    ${pkgs.coreutils}/bin/touch "$1/${readyFile}"
  '';
  removeReady = "${pkgs.coreutils}/bin/rm -f ${runtime}/${readyFile}";
  hook = pkgs.writeShellScript "codex-harness-report" ''
    if [[ "''${1-}" == ${lib.escapeShellArg cfg.hookHome} && -f "''${XDG_RUNTIME_DIR:?}/nexus/${cfg.place}/${readyFile}" ]]; then
      exec ${translator}/bin/codex-harness-hook
    fi
    exit 0
  '';
  hookCommand = "if [ -x ${lib.escapeShellArg markerPath} ]; then exec ${lib.escapeShellArg markerPath} ${lib.escapeShellArg cfg.hookHome}; fi";
  hookMerge = pkgs.writeShellApplication {
    name = "merge-codex-harness-hooks";
    runtimeInputs = [ pkgs.coreutils pkgs.jq ];
    text = ''
      umask 077
      directory=$1
      mkdir -p -- "$directory"
      destination="$directory/hooks.json"
      input="$destination"
      if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
        printf '%s\n' "Expected a regular hooks file: $destination" >&2
        exit 1
      fi
      temporary=$(mktemp "$destination.XXXXXX")
      trap 'rm -f -- "$temporary"' EXIT
      if [[ ! -e $destination ]]; then
        input=/dev/stdin
      fi
      jq -e --arg marker ${lib.escapeShellArg "/${marker}"} --arg command ${lib.escapeShellArg hookCommand} \
        --argjson timeout ${toString cfg.hookTimeoutSeconds} --argjson events ${lib.escapeShellArg (builtins.toJSON cfg.hookEvents)} \
        -f ${deployment}/merge-hooks.jq "$input" > "$temporary" <<< '{}'
      mv -T -- "$temporary" "$destination"
    '';
  };
  serviceDefaults = {
    Type = "exec";
    UMask = "0077";
    Restart = "on-failure";
    RestartSec = cfg.restartDelay;
    TimeoutStartSec = cfg.startupTimeout;
    Environment = [
      "XDG_CONFIG_HOME=${config.xdg.configHome}"
      "XDG_RUNTIME_DIR=%t"
      "XDG_STATE_HOME=%S"
    ];
  };
  absolutePath = lib.types.strMatching "/[^«»\n\r]*";
in
{
  options.criomosHome.codexHarness = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.elem "AgentStack" user.capabilities;
      description = "Serve the declared Codex Harness Nexus and its translator for this user.";
    };
    place = lib.mkOption {
      type = lib.types.strMatching "[a-z][a-z0-9-]*";
      default = "main";
      description = "The declared Nexus place used by both servers and all clients.";
    };
    rowCount = lib.mkOption {
      type = lib.types.ints.positive;
      default = 256;
      description = "Maximum rows the Nexus asks a rollout watch to read at once.";
    };
    threadDatabase = lib.mkOption {
      type = lib.types.nullOr absolutePath;
      default = null;
      description = "Read-only Codex thread database used to locate a rollout absent from the hook; null leaves the committed setting alone.";
    };
    restartDelay = lib.mkOption {
      type = lib.types.str;
      default = "2s";
      description = "Delay after failure before the Harness Nexus or translator is restarted.";
    };
    startupTimeout = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "Systemd deadline for the sockets, subscription handshake and initial configuration.";
    };
    hookHome = lib.mkOption {
      type = lib.types.nullOr absolutePath;
      default = if config.criomosHome.codexPlain.enable then config.criomosHome.codexPlain.homeDirectory else null;
      description = "Codex home whose hooks carry events into this place; null serves clients without installing hooks.";
    };
    hookEvents = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "SessionStart" "PermissionRequest" "PostToolUse" "PostCompact" ]);
      default = [ "SessionStart" "PermissionRequest" "PostToolUse" "PostCompact" ];
      description = "Codex events sent to the Harness Nexus hook.";
    };
    hookTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Codex deadline in seconds for a Harness Nexus hook invocation.";
    };
  };

  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = lib.elem cfg.place places.places;
        message = "The Codex Harness Nexus place must be declared in criomosHome.nexusPlaces.places.";
      }
      {
        assertion = lib.length (lib.unique cfg.hookEvents) == lib.length cfg.hookEvents;
        message = "Each Codex Harness hook event must be named once.";
      }
    ];
    xdg.configFile."nexus/codex-harness-nexus.datom".text = "{ ${cfg.place} }\n";
    home.packages = [ translator ];
    systemd.user.services = {
      ${nexusUnit} = {
        Unit = {
          Description = "Codex Harness Nexus 0.4.0";
          After = [ places.unit ];
          Wants = [ "${translatorUnit}.service" ];
        };
        Service = serviceDefaults // {
          ExecStartPre = "${readiness} clear ${nexusSockets}";
          ExecStart = "${nexus}/bin/codex-harness-nexus ${place}";
          ExecStartPost = "${readiness} wait ${runtime}/codex-harness-meta.sock";
          ExecStopPost = "${readiness} clear ${nexusSockets}";
        };
        Install.WantedBy = [ "default.target" ];
      };
      ${translatorUnit} = {
        Unit = {
          Description = "Codex Harness translator 0.4.0";
          After = [ "${nexusUnit}.service" ];
          BindsTo = [ "${nexusUnit}.service" ];
          PartOf = [ "${nexusUnit}.service" ];
        };
        Service = serviceDefaults // {
          ExecStartPre = [ removeReady "${readiness} clear ${translatorSockets}" ];
          ExecStart = "${translator}/bin/codex-harness-translator ${place}";
          ExecStartPost = "${configure} ${runtime}";
          ExecStopPost = [ removeReady "${readiness} clear ${translatorSockets}" ];
        };
      };
    };
    home.file = lib.mkIf (cfg.hookHome != null) {
      ${marker}.source = hook;
    };
    home.activation = lib.mkIf (cfg.hookHome != null) {
      codexHarnessHookFeature = inputs.hexis.lib.mkManagedConfig {
        inherit lib pkgs;
        hexis = inputs.hexis.packages.${system}.default;
        file = "${cfg.hookHome}/config.toml";
        declared.features = {
          hooks = true;
        } // lib.optionalAttrs sharedPlain {
          multi_agent_v2.multi_agent_mode_hint_text = multiAgentModeHint;
        };
        modes = {
          "/features/hooks" = "always";
        } // lib.optionalAttrs sharedPlain {
          "/features/multi_agent_v2/multi_agent_mode_hint_text" = "always";
        };
      };
      codexHarnessHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${hookMerge}/bin/merge-codex-harness-hooks ${lib.escapeShellArg cfg.hookHome}
      '';
    };
  };
}
