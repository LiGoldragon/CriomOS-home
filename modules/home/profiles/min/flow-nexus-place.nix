# A Flow Nexus unit that starts in its place (vision:nexus-v1, "A Nexus starts
# in its place"): `slug` is the version without its dots (0533), `version`
# the dotted one (0.53.3). It is started with the place's name, `main` or
# `next`, and reads nothing at start but its Place, from its place file,
# $XDG_CONFIG_HOME/nexus/<place>/flow-nexus.signal: the place's Runtime
# (flow.sock, flow-meta.sock) and State (flow.sema). The file is written at
# every activation, with translator's nexus-configure, for it holds the user's
# runtime directory, /run/user/<uid>/nexus/<place>, which no declaration holds;
# a Nexus with no place file refuses to start, naming it, so Home always
# writes it. Nothing else reaches the unit: no environment, no other argument.
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
# unit is Type=notify. The executable holds no configuration: a new memory
# starts unconfigured, answering Unconfigured. Its configuration is declared
# after it by its configure unit, ordered After= and Requires= it, which hands
# the running Nexus one Configure per family through flow-nexus-meta,
# Configure.Nexus first; the Nexus takes each at once and answers Configured
# with the change it was given, echoed whole, also when its memory already
# holds it. A changed declaration restarts the configure unit only, never the
# Nexus.
#
# Its clients take the datom and nothing else (vision:nexus-v1): the place
# name is read from one configuration datom,
# $XDG_CONFIG_HOME/nexus/flow-nexus.datom, `{ <place> }`, and the sockets are
# found in the Runtime of that place's place file, under the same
# configuration home; they read no XDG_RUNTIME_DIR. This version's own clients
# (flow-nexus-<version>, flow-nexus-meta-<version>) and its configure unit run
# with XDG_CONFIG_HOME set to `placeConfiguration`, a directory whose
# nexus/flow-nexus.datom names this version's place and whose
# nexus/<place>/flow-nexus.signal is the place file Home wrote, so they reach
# it whatever the user's configuration names; no place is ever typed. The
# user's ~/.config/nexus/flow-nexus.datom is declared by the version at main
# (flow-0550.nix).
#
# The hook command it writes into every Claude flow is
# ~/.local/bin/flow-nexus-hook when this version holds the stable hook
# (stableHook): Home points that path at this version's flow-nexus-hook, and the configure unit declares it as the
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
  stableHookPath = ".local/bin/flow-nexus-hook";
  # The Nexus a memory is configured with, as data: the configure unit
  # declares it whole to the running Nexus.
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
  # Flow <version>, built once: its executable holds no configuration.
  runtime = inputs."flow-${slug}".packages.${system}.default;
  # translator's nexus-configure, the one tool that compiles a place written
  # in datom into the place file every Nexus reads at start.
  nexusConfigure = inputs."flow-${slug}".packages.${system}.nexus-configure;
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
  # ConfigureNexus as meta-signal-flow reads it: from 75.0.0 (Flow 0.54.3)
  # its last field is the HerdrSessionName every launch opens in, after the
  # Option<PresentationPrompt.String>; earlier versions end at the prompt.
  nexusQuery = pkgs.writeText "flow-${slug}-nexus.datom" ''
    Configure.Nexus.{ ${text nexus.sourceRoot} ${endpoint nexus.stableCodex} ${endpoint nexus.nextCodex} ${vector (map profile nexus.harnessProfiles)} ${vector nexus.metaAspects} ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.socket)
    } ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.binary)
    } ${text nexus.curriculumNexusPath} ${toString nexus.lease} ${
      option (if cfg.presentationPrompt == null then null else text cfg.presentationPrompt)
    }${lib.optionalString (cfg.herdrSession != null) " ${text cfg.herdrSession}"} }
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
  # An owner-declared family, by its written path; another, from this version's configuration directory.
  declaredPath =
    family:
    "${cfg.declarationDirectory}/${builtins.unsafeDiscardStringContext (baseNameOf (toString cfg.ownerDeclarations.${family}))}";
  declared =
    family:
    if cfg.ownerDeclarations ? ${family} then
      declaredPath family
    else
      "${cfg.configurationDirectory + "/${family}.datom"}";
  # Each permaflow carries its own leave-outs in the metaflow declaration
  # (Flow 0.55.0, meta-signal-flow 78); there is no leave-out family.
  queries = [
    "${nexusQuery}"
    (declared "models")
    (declared "thresholds")
    "${sendServersQuery}"
  ]
  ++ lib.optional cfg.stableHook "${harnessHookQuery}"
  ++ [
    # The permaflow declarations, after the models their leave-outs' harness is read from.
    (declared "metaflows")
  ]
  ++ map (file: "${cfg.configurationDirectory + "/${file}"}") cfg.trailingConfigurationFiles;
  # The place file of this version's place, where the Nexus reads it: under
  # the user's configuration home, written at activation (it holds the user's
  # runtime directory).
  placeFile = "${config.xdg.configHome}/nexus/${cfg.place}/flow-nexus.signal";
  # The configuration home of this version's clients: its
  # nexus/flow-nexus.datom names this version's place, and the place file it
  # names is the one Home wrote, reached through a link that is read at run
  # time, so the clients and the Nexus hold one place.
  placeConfiguration =
    pkgs.runCommand "flow-${slug}-place-configuration" { } ''
      mkdir -p $out/nexus/${cfg.place}
      echo '{ ${cfg.place} }' > $out/nexus/flow-nexus.datom
      ln -s ${placeFile} $out/nexus/${cfg.place}/flow-nexus.signal
    '';
  # Runs once the Nexus has announced readiness, its sockets bound: each
  # query goes to the running Nexus through flow-nexus-meta, its configuration
  # naming this version's place, in order, and each must be taken.
  # Arguments: the query files.
  configure = pkgs.writeShellApplication {
    name = "configure-flow-${slug}";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      : "''${XDG_RUNTIME_DIR:?the unit runs with XDG_RUNTIME_DIR}"
      export XDG_CONFIG_HOME=${placeConfiguration}
      for query in "$@"; do
        body=$(<"$query")
        if ! reply=$(${runtime}/bin/flow-nexus-meta "''${body//${runtimeToken}/$XDG_RUNTIME_DIR}"); then
          printf 'Flow Nexus ${version} at ${cfg.place} did not answer %s\n' "$query" >&2
          exit 1
        fi
        case "$reply" in
          Configured.*) printf '%s Configured\n' "$(basename "$query")" ;;
          *) printf 'Flow Nexus ${version} refused %s: %s\n' "$query" "$reply" >&2; exit 1 ;;
        esac
      done
    '';
  };
  # The <version> clients under their versioned names, reaching this
  # version's place: `flow-nexus-<version> Metaflows` is `flow-nexus
  # Metaflows` with the configuration naming this version's place.
  versionedCli =
    name: raw:
    pkgs.writeShellScript name ''
      XDG_CONFIG_HOME=${placeConfiguration} exec ${runtime}/bin/${raw} "$*"
    '';
  clients = pkgs.runCommand "flow-${slug}-clients" { } ''
    mkdir -p $out/bin
    ln -s ${versionedCli "flow-nexus-${version}" "flow-nexus"} $out/bin/flow-nexus-${version}
    ln -s ${versionedCli "flow-nexus-meta-${version}" "flow-nexus-meta"} $out/bin/flow-nexus-meta-${version}
  '';
  # The place's two directories, as the place file holds them. The runtime
  # directory is the user manager's own %t, /run/user/<uid>; a Lojix activation
  # runs without XDG_RUNTIME_DIR, so the uid names it. The state directory is
  # %S, the configured XDG state home. The directories are shared with every
  # other Nexus at the same place and declared by nexus-places.nix, so the unit
  # names no RuntimeDirectory or StateDirectory that a stop would remove.
  placeText = "{ ${text cfg.place} ${text "\${runtimeRoot}/nexus/${cfg.place}"} ${text "${config.xdg.stateHome}/nexus/${cfg.place}"} }";
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
    declarationDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/state/flow-declarations";
      description = "Where the owner's declarations are written for the configure unit to replay.";
    };
    ownerDeclarations = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''{ models = "''${inputs.owner}/models.datom"; }'';
      description = "The families the owner declares in his own repository, models, thresholds and metaflows, each named to its file there. Activation writes each into declarationDirectory under its own file name, a change to any restarts the configure unit, which replays it. A family absent here is taken from configurationDirectory.";
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
      description = "Whether ~/.local/bin/flow-nexus-hook is this version's flow-nexus-hook and the Nexus's declared HarnessHook, the path it writes into the flows it launches; one version holds it at a time.";
    };
    memoryLimit = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            maximum = lib.mkOption {
              type = lib.types.str;
              description = "The unit's MemoryMax: the size at which the kernel stops the Nexus.";
            };
            swapMaximum = lib.mkOption {
              type = lib.types.str;
              description = "The unit's MemorySwapMax.";
            };
          };
        }
      );
      default = null;
      description = "The memory the Nexus unit is held to; null holds it to none. It is part of the unit, so it exists only where the unit does.";
    };
    presentationPrompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Text the Psyche core Primary system prompt carries; null carries none.";
    };
    herdrSession = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The one Herdr session every launch opens its pane in (Flow 0.54.3 and later, whose Configure.Nexus names it); null for a version before 0.54.3, whose Configure.Nexus has no such field.";
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
    placeConfiguration = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = placeConfiguration;
      description = "A configuration home whose nexus/flow-nexus.datom names this version's place: its clients and its configure unit read their place from it.";
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
    # The place file the Nexus and its clients read, written at every
    # activation: it holds the user's runtime directory, /run/user/<uid>/...,
    # which no declaration holds, and with no place file the Nexus refuses to
    # start. It is written before the units are reloaded, so a Nexus that
    # restarts at the switch finds it.
    home.activation.${"flowPlace${slug}"} = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
      runtimeRoot="/run/user/$(id -u)"
      placeDatom="$(mktemp)"
      printf '%s\n' "${placeText}" > "$placeDatom"
      run ${nexusConfigure}/bin/nexus-configure "Compile.{ «$placeDatom» «${placeFile}» }"
      rm -f "$placeDatom"
    '';
    home.file = lib.mkMerge [
      (lib.mkIf cfg.stableHook {
        ${stableHookPath}.source = "${runtime}/bin/flow-nexus-hook";
      })
      (lib.mapAttrs' (
        family: source:
        lib.nameValuePair (lib.removePrefix "${home}/" (declaredPath family)) {
          inherit source;
          force = true;
        }
      ) cfg.ownerDeclarations)
    ];
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
        ExecStart = "${runtime}/bin/flow-nexus-daemon ${cfg.place}";
        Restart = "on-failure";
        RestartSec = "100ms";
      }
      // lib.optionalAttrs (cfg.memoryLimit != null) {
        MemoryMax = cfg.memoryLimit.maximum;
        MemorySwapMax = cfg.memoryLimit.swapMaximum;
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
        X-Restart-Triggers = map toString (lib.attrValues cfg.ownerDeclarations);
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
