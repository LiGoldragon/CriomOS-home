# A Flow Nexus unit that starts in its place (vision:nexus-v1, "A Nexus starts
# in its place"): `slug` is the version without its dots (0533), `version`
# the dotted one (0.53.3). It is started with one datom, its place:
# `{ <place> %t/nexus/<place> %S/nexus/<place> }`, its sockets in Runtime
# (flow.sock, flow-meta.sock) and its memory in State (flow.sema). Nothing
# else reaches it from the unit: no environment, no other argument.
#
# Two places are two names: the stable version runs at `main`, a candidate
# at `next` with its own memory. A version becomes main by being started at
# `main`, the previous version at main having stopped; it opens main's
# memory and upgrades it in place. Every flow-facing path names the place,
# never a version: the hook settings of every Claude flow name
# $XDG_RUNTIME_DIR/nexus/main/flow.sock, the socket whichever version is
# main serves.
#
# The place's two directories are shared with every other Nexus at it and
# declared once by nexus-places.nix; the unit names no RuntimeDirectory or
# StateDirectory, is ordered after the unit that makes them, and asserts its
# place is declared.
#
# The Nexus announces readiness (READY=1 once both sockets are bound), so its
# unit is Type=notify. On a fresh memory it starts with the configuration
# built into its executable. Its configuration is declared after it by its
# configure unit, ordered After= and Requires= it, which hands the running
# Nexus one Configure per family through flow-meta; the Nexus takes each at
# once and answers Configured.Replaced, or Configured.Unchanged when its
# memory already holds it. A changed declaration restarts the configure
# unit only, never the Nexus.
#
# The hook command it writes into every Claude flow is ~/.local/bin/flow-hook
# when this version holds the stable hook (stableHook): Home points that
# path at this version's flow-hook, and the configure unit declares it as the
# Nexus's HarnessHook. The version that takes stableHook over repoints it.
{ version, slug }:
{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  optionName = "flow${slug}";
  cfg = config.criomosHome.${optionName};
  places = config.criomosHome.nexusPlaces;
  # The user's runtime directory is known only to the running unit (systemd
  # sets XDG_RUNTIME_DIR, %t in the unit); no uid is declared here. A path in
  # a query names it by this token, which configure-flow-<slug> replaces with
  # $XDG_RUNTIME_DIR before sending.
  runtimeToken = "@XDG_RUNTIME_DIR@";
  system = pkgs.stdenv.hostPlatform.system;
  home = config.home.homeDirectory;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  pathOnly = builtins.unsafeDiscardStringContext;
  nextCodexHome = "${home}/.codex-next-${config.criomosHome.codexNextCandidate.hash}";
  message = inputs.message.packages.${system}.default;
  # The hook command every Claude flow this Nexus launches runs, one path
  # across versions; Home points it at the version holding stableHook.
  stableHookPath = ".local/bin/flow-hook";
  # The Nexus a memory is configured with, as data. The build bakes the part
  # mkFlowPackage takes into the executable, for a fresh memory to start
  # with; the configure unit declares it whole to the running Nexus.
  nexus = {
    sourceRoot = "${home}/primary";
    stableCodex = {
      clientPath = pathOnly "${config.criomosHome.herdr.stableCodexClientPackage}/bin/codex-stable-flow-client";
      home = "${home}/.codex-next";
      controlSocketPath = "${home}/.codex-next/app-server-control/app-server-control.sock";
      roster = [
        "gpt-5.6-sol"
        "gpt-5.6-luna"
      ];
    };
    nextCodex = {
      clientPath = pathOnly "${config.criomosHome.codexNextCandidate.clientPackage}/bin/codex-next-flow-client";
      home = nextCodexHome;
      controlSocketPath = "${nextCodexHome}/app-server-control/app-server-control.sock";
      roster = [
        "gpt-6.1-sol"
        "gpt-6-sol"
        "gpt-6-luna"
        "gpt-6-astra"
      ];
    };
    harnessProfiles = [
      {
        harnessKind = "Claude";
        commandSigils = [
          "/"
          "!"
          "#"
        ];
        interruptKeys = [
          "esc"
          "esc"
        ];
        submitKeys = [ "enter" ];
      }
      {
        harnessKind = "Codex";
        commandSigils = [
          "/"
          "!"
        ];
        interruptKeys = [ "esc" ];
        submitKeys = [ ];
      }
    ];
    metaAspects = [ "Psyche" ];
    curriculumNexusPath = "${runtimeToken}/curriculum/curriculum.sock";
    lease = 60;
  };
  # Flow <version> is built only through mkFlowPackage: its executable carries
  # the configuration a fresh memory starts with.
  runtime = inputs."flow-${slug}".lib.${system}.mkFlowPackage {
    defaultConfiguration = {
      inherit (nexus)
        sourceRoot
        stableCodex
        nextCodex
        harnessProfiles
        metaAspects
        ;
      presentationPrompt = cfg.presentationPrompt;
      # mkFlowPackage asks for an absolute path to derive a fresh memory's
      # Curriculum socket from. The real one is the running unit's runtime
      # directory, which no declaration holds; the configure unit declares
      # the Nexus with it at every start, so this value is never launched
      # from.
      runtimeDirectory = "/run/flow-${slug}-undeclared-runtime";
    };
  };
  # Datom rendering of the attribute-held families.
  text = value: "«${value}»";
  vector = values: "[ ${lib.concatMapStrings (value: "${value} ") values}]";
  option = value: if value == null then "None" else "Some.${value}";
  endpoint =
    value:
    "{ ${text value.clientPath} ${text value.home} ${text value.controlSocketPath} ${vector value.roster} }";
  profile =
    value:
    "{ ${value.harnessKind} ${vector (map text value.commandSigils)} ${vector value.interruptKeys} ${vector value.submitKeys} }";
  sendServer =
    value: "{ ${text value.codexAppServerBinary} ${text value.mcpSendServerBinary} }";
  # ConfigureNexus as meta-signal-flow 72.0.0 reads it; its last field is
  # the Option<PresentationPrompt.String>.
  nexusQuery = pkgs.writeText "flow-${slug}-nexus.datom" ''
    Configure.Nexus.{ ${text nexus.sourceRoot} ${endpoint nexus.stableCodex} ${endpoint nexus.nextCodex} ${vector (map profile nexus.harnessProfiles)} ${vector nexus.metaAspects} ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.socket)
    } ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.binary)
    } ${text nexus.curriculumNexusPath} ${toString nexus.lease} ${
      option (if cfg.presentationPrompt == null then null else text cfg.presentationPrompt)
    } }
  '';
  sendServersQuery = pkgs.writeText "flow-${slug}-send-servers.datom" ''
    Configure.SendServers.${vector (map sendServer cfg.sendServers)}
  '';
  # The hook command written into every Claude flow: the stable path.
  harnessHookQuery = pkgs.writeText "flow-${slug}-harness-hook.datom" ''
    Configure.HarnessHook.${text "${home}/${stableHookPath}"}
  '';
  # One Configure each, in this order: the Nexus first, the investigation seat
  # after the metaflows it is launched from.
  #
  # FIXME(Mind core): Maintained is state, set by signal, never declared. Flow
  # <version> stores it inside the definition family: Continuity is a field of
  # ConfigureMetaflow (meta-signal-flow ethos/signal.ethos), and
  # Configure.Metaflows replaces that family whole, so this declaration
  # resets every seat a signal moved. No signal sets Continuity on one
  # metaflow. Until Continuity is its own state family with its own signal,
  # every row of metaflows.datom is OnDemand.
  queries = [
    "${nexusQuery}"
    "${cfg.configurationDirectory + "/models.datom"}"
    "${cfg.configurationDirectory + "/thresholds.datom"}"
    "${cfg.configurationDirectory + "/leave-outs.datom"}"
    "${sendServersQuery}"
  ]
  ++ lib.optional cfg.stableHook "${harnessHookQuery}"
  ++ [
    # The live declaration corpus is owner state and must not be reset by a source snapshot.
    cfg.declarationPath
  ]
  ++ map (file: "${cfg.configurationDirectory + "/${file}"}") cfg.trailingConfigurationFiles;
  # Runs once the Nexus has announced readiness, its sockets bound: each
  # query goes to the running Nexus through flow-meta at its place, in order,
  # and each must be taken. Arguments: the query files.
  configure = pkgs.writeShellApplication {
    name = "configure-flow-${slug}";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      : "''${XDG_RUNTIME_DIR:?the unit runs with XDG_RUNTIME_DIR}"
      for query in "$@"; do
        body=$(<"$query")
        if ! reply=$(${runtime}/bin/flow-meta ${lib.escapeShellArg cfg.place} "''${body//${runtimeToken}/$XDG_RUNTIME_DIR}"); then
          printf 'Flow Nexus ${version} at ${cfg.place} did not answer %s\n' "$query" >&2
          exit 1
        fi
        case "$reply" in
          Configured.Replaced|Configured.Unchanged) printf '%s %s\n' "$(basename "$query")" "$reply" ;;
          *) printf 'Flow Nexus ${version} refused %s: %s\n' "$query" "$reply" >&2; exit 1 ;;
        esac
      done
    '';
  };
  # The <version> clients under their versioned names, reaching this
  # version's place: `flow-<version> Metaflows` is `flow <place> Metaflows`.
  versionedCli =
    name: raw:
    pkgs.writeShellScript name ''
      exec ${runtime}/bin/${raw} ${lib.escapeShellArg cfg.place} "$*"
    '';
  clients = pkgs.runCommand "flow-${slug}-clients" { } ''
    mkdir -p $out/bin
    ln -s ${versionedCli "flow-${version}" "flow"} $out/bin/flow-${version}
    ln -s ${versionedCli "flow-meta-${version}" "flow-meta"} $out/bin/flow-meta-${version}
  '';
  # The place datom the Nexus is started with. %t is $XDG_RUNTIME_DIR and %S
  # $XDG_STATE_HOME, else ~/.local/state, for a user unit: the roots
  # vision:nexus-v1 names. The directories are shared with every other Nexus
  # at the same place and declared by nexus-places.nix, so the unit names no
  # RuntimeDirectory or StateDirectory that a stop would remove.
  place = "{ ${text cfg.place} ${text "%t/nexus/${cfg.place}"} ${text "%S/nexus/${cfg.place}"} }";
in
{
  options.criomosHome.${optionName} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.elem "AgentStack" user.capabilities;
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "flow-nexus-${slug}";
    };
    configureUnit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "flow-configure-${slug}";
    };
    place = lib.mkOption {
      type = lib.types.enum [
        "main"
        "next"
      ];
      default = "next";
      description = "The place this version runs at: main, the stable one every flow reports to, or next, a candidate with its own memory.";
    };
    declarationPath = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/state/flow-declarations/metaflows.datom";
      description = "The owner's mutable metaflow declaration file this Nexus is configured from.";
    };
    configurationDirectory = lib.mkOption {
      type = lib.types.path;
      default = ./flow-nexus-config;
      description = "The directory of this version's immutable configuration queries, in its own schema.";
    };
    trailingConfigurationFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "harness-flags.datom"
        "investigation.datom"
        "default-minutes.datom"
      ];
      description = "The query files of the configuration directory declared after the metaflow declaration, in order.";
    };
    sendServers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            codexAppServerBinary = lib.mkOption { type = lib.types.str; };
            mcpSendServerBinary = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [
        {
          codexAppServerBinary = "${config.criomosHome.codexNextCandidate.package}/bin/codex";
          mcpSendServerBinary = "${message}/bin/message-mcp-send";
        }
      ];
      description = "The MCP send servers this Nexus trusts, each paired with its Codex app-server; an empty list trusts none.";
    };
    messageNexus = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            socket = lib.mkOption { type = lib.types.str; };
            binary = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = {
        socket = "${runtimeToken}/message/message.sock";
        binary = "${message}/bin/message-nexus";
      };
      description = "The Message Nexus this Nexus admits as a meta peer; null admits none.";
    };
    stableHook = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether ~/.local/bin/flow-hook is this version's flow-hook and the Nexus's declared HarnessHook, the path it writes into the flows it launches; one version holds it at a time.";
    };
    presentationPrompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Text the Psyche core Primary system prompt carries; null carries none.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runtime;
    };
    clients = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = clients;
    };
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = builtins.elem cfg.place places.places;
        message = "criomosHome.${optionName}.place ${cfg.place} is not one of criomosHome.nexusPlaces.places.";
      }
    ];
    home.packages = [ clients ];
    home.file = lib.mkIf cfg.stableHook {
      ${stableHookPath}.source = "${runtime}/bin/flow-hook";
    };
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus ${version} at ${cfg.place}";
        # The Nexus composes every launch's context through Curriculum
        # (ComposeStartup at Start, wake and resume); without it no flow starts.
        Wants = [ "curriculum-nexus.service" ];
        After = [
          "curriculum-nexus.service"
          places.unit
        ];
      };
      Service = {
        # Started once both its sockets listen: READY=1.
        Type = "notify";
        WorkingDirectory = "%h";
        ExecStart = "${runtime}/bin/flow-nexus \"${place}\"";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
    # The configuration, declared to the running Nexus. It starts with the
    # Nexus and after it (Type=notify: after its sockets are bound), and is
    # stopped or restarted with it; a changed declaration restarts it alone.
    systemd.user.services.${cfg.configureUnit} = {
      Unit = {
        Description = "Flow Nexus ${version} configuration at ${cfg.place}";
        Requires = [ "${cfg.unit}.service" ];
        After = [ "${cfg.unit}.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${configure}/bin/configure-flow-${slug} ${lib.escapeShellArgs queries}";
      };
      Install.WantedBy = [ "${cfg.unit}.service" ];
    };
  };
}
