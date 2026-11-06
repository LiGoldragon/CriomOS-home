# A Flow Nexus unit as a function of its version: `slug` is the version
# without its dot (048), `version` the dotted one (0.48). flow-048.nix and
# flow-049.nix instantiate it; the declared configuration (flow-nexus-config/)
# is one source for every version.
{ version, slug }:
{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
# Flow Nexus <version>, a versioned unit beside the running Flow Nexus 0.44. It
# opens its own store and serves its own sockets; nothing of 0.44 is touched.
#
# A <version> client names the Nexus's socket inside its Invocation datom
# (`{ «socket» Query }`); no raw <version> client has a default socket. The
# installed flow-<version> and flow-meta-<version> supply this Nexus's sockets. The
# Nexus writes its ordinary socket into the hook configuration of every
# Claude pane it launches, so its own flows report back to it with nothing
# read from the environment.
let
  optionName = "flow${slug}";
  cfg = config.criomosHome.${optionName};
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
  # The Nexus a store is configured with, as data. The build bakes the part
  # mkFlowPackage takes into the executable, for a new store to open with;
  # the ExecStartPre configure step declares it whole before the Nexus starts.
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
  # Flow <version> is built only through mkFlowPackage: its executable carries the
  # configuration a new, unconfigured store opens with.
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
      # mkFlowPackage asks for an absolute path to derive a new store's
      # Curriculum socket from. The real one is the running unit's runtime
      # directory, which no declaration holds; configure-flow-<slug> declares the
      # Nexus with it before every start, so this value is never launched from.
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
  # ConfigureNexus at meta-signal-flow 7a19023, the shape flow cfcbf5c reads;
  # its last field is the Option<PresentationPrompt.String>.
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
  # One Configure each, in this order: the Nexus first, the investigation seat
  # after the metaflows it is launched from.
  #
  # FIXME(Mind core): Maintained is state, set by signal, never declared. Flow
  # <version> stores it inside the definition family: Continuity is a field of
  # ConfigureMetaflow (meta-signal-flow ethos/signal.ethos), and
  # Configure.Metaflows replaces that family whole, so this start-time
  # declaration resets every seat a signal moved. No signal sets Continuity
  # on one metaflow. Until Continuity is its own state family with its own
  # signal, every row of metaflows.datom is OnDemand.
  queries = [
    "${nexusQuery}"
    "${cfg.configurationDirectory + "/models.datom"}"
    "${cfg.configurationDirectory + "/thresholds.datom"}"
    "${cfg.configurationDirectory + "/leave-outs.datom"}"
    "${sendServersQuery}"
    # The live declaration corpus is owner state and must not be reset by a source snapshot.
    cfg.declarationPath
    "${cfg.configurationDirectory + "/harness-flags.datom"}"
    "${cfg.configurationDirectory + "/investigation.datom"}"
    "${cfg.configurationDirectory + "/default-minutes.datom"}"
  ];
  # Runs before the Nexus starts, at every start, so the declared
  # configuration is in the store before any worker runs. `--configure-only`
  # opens the store, serves one Configure on the meta socket and exits, so
  # each query gets its own run. Configure replaces one family whole and
  # answers Unchanged when the store already holds the declaration, so a
  # repeat writes nothing. Arguments: the Start datom, the meta socket path,
  # then the query files.
  configure = pkgs.writeShellApplication {
    name = "configure-flow-${slug}";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      : "''${XDG_RUNTIME_DIR:?the unit runs with XDG_RUNTIME_DIR}"
      start="$1"
      socket="$2"
      shift 2
      for query in "$@"; do
        ${runtime}/bin/flow-nexus --configure-only "$start" &
        child=$!
        # A stale pathname is not readiness: observe the listening socket
        # held by this child, without consuming its one request.
        child_listens() {
          local inode fd target
          [ -S "$socket" ] || return 1
          while IFS= read -r inode; do
            for fd in /proc/"$child"/fd/*; do
              target=$(readlink "$fd" 2>/dev/null) || continue
              if [ "$target" = "socket:[$inode]" ]; then return 0; fi
            done
          done < <(awk -v socket="$socket" \
            '$4 == "00010000" && $5 == "0001" && $6 == "01" && $8 == socket { print $7 }' \
            "/proc/$child/net/unix")
          return 1
        }
        for _attempt in $(seq 1 100); do
          if child_listens; then break; fi
          if ! kill -0 "$child" 2>/dev/null; then
            echo "Flow configuration-only Nexus exited before its socket listened" >&2
            wait "$child" || true
            exit 1
          fi
          sleep 0.05
        done
        if ! child_listens; then
          kill "$child" 2>/dev/null || true
          wait "$child" || true
          echo "Flow configuration-only Nexus did not listen on $socket" >&2
          exit 1
        fi
        body=$(<"$query")
        # A query the client refuses never reaches the waiting Nexus, which
        # would otherwise wait for it forever.
        if ! reply=$(${runtime}/bin/flow-meta "{ «$socket» ''${body//${runtimeToken}/$XDG_RUNTIME_DIR} }"); then
          kill "$child" 2>/dev/null || true
          wait "$child" || true
          printf 'Flow Nexus ${version} did not accept %s\n' "$query" >&2
          exit 1
        fi
        wait "$child"
        case "$reply" in
          Configured.Replaced|Configured.Unchanged) printf '%s %s\n' "$(basename "$query")" "$reply" ;;
          *) printf 'Flow Nexus ${version} refused %s: %s\n' "$query" "$reply" >&2; exit 1 ;;
        esac
      done
    '';
  };
  # The <version> clients under their versioned names. The raw <version> client names
  # its Nexus's socket inside the Invocation datom; each versioned CLI
  # supplies this Nexus's socket, so `flow-<version> Metaflows` reaches it from
  # any environment. The arguments are the Query.
  versionedCli =
    name: raw: socket:
    pkgs.writeShellScript name ''
      exec ${runtime}/bin/${raw} "{ «''${XDG_RUNTIME_DIR:?}/${cfg.runtimeDirectory}/${socket}» $* }"
    '';
  clients = pkgs.runCommand "flow-${slug}-clients" { } ''
    mkdir -p $out/bin
    ln -s ${versionedCli "flow-${version}" "flow" "flow.sock"} $out/bin/flow-${version}
    ln -s ${versionedCli "flow-meta-${version}" "flow-meta" "flow-meta.sock"} $out/bin/flow-meta-${version}
  '';
  socketDirectory = "%t/${cfg.runtimeDirectory}";
  start = "{ «${socketDirectory}/flow.sock» «${socketDirectory}/flow-meta.sock» «%h/.local/state/${cfg.stateDirectory}/flow.sema» None }";
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
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-${slug}";
      description = "Directory under ~/.local/state holding this Nexus's flow.sema.";
    };
    runtimeDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-${slug}";
      description = "Directory under $XDG_RUNTIME_DIR holding this Nexus's flow.sock and flow-meta.sock.";
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
        assertion =
          cfg.stateDirectory != "flow-harnessflags" && cfg.runtimeDirectory != "flow-harnessflags";
        message = "Flow Nexus ${version} must not open the 0.44 store or sockets";
      }
    ];
    home.packages = [ clients ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus ${version}";
        # The Nexus composes every launch's context through Curriculum
        # (ComposeStartup at Start, wake and resume); without it no flow starts.
        Wants = [ "curriculum-nexus.service" ];
        After = [ "curriculum-nexus.service" ];
      };
      Service = {
        Type = "simple";
        WorkingDirectory = "%h";
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        RuntimeDirectory = cfg.runtimeDirectory;
        RuntimeDirectoryMode = "0700";
        ExecStart = "${runtime}/bin/flow-nexus \"${start}\"";
        ExecStartPre = "${configure}/bin/configure-flow-${slug} ${lib.escapeShellArgs ([ start "${socketDirectory}/flow-meta.sock" ] ++ queries)}";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
