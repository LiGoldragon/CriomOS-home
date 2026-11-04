{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
# Flow Nexus 0.48, a versioned unit beside the running Flow Nexus 0.44. It
# opens its own store and serves its own sockets; nothing of 0.44 is touched.
#
# A 0.48 client names the Nexus's socket inside its Invocation datom
# (`flow '{ «socket» Query }'`, `flow-meta '{ «meta-socket» Query }'`);
# no 0.48 client has a default socket. The Nexus writes its ordinary socket
# into the hook configuration of every Claude pane it launches, so its own
# flows report back to it with nothing read from the environment.
let
  cfg = config.criomosHome.flow048;
  # The user's runtime directory is known only to the running unit (systemd
  # sets XDG_RUNTIME_DIR, %t in the unit); no uid is declared here. A path in
  # a query names it by this token, which configure-flow-048 replaces with
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
  # Flow 0.48 is built only through mkFlowPackage: its executable carries the
  # configuration a new, unconfigured store opens with.
  runtime = inputs.flow-048.lib.${system}.mkFlowPackage {
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
      # directory, which no declaration holds; configure-flow-048 declares the
      # Nexus with it before every start, so this value is never launched from.
      runtimeDirectory = "/run/flow-048-undeclared-runtime";
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
  # ConfigureNexus at meta-signal-flow 7a19023, the shape flow cfcbf5c reads;
  # its last field is the Option<PresentationPrompt.String>.
  nexusQuery = pkgs.writeText "flow-048-nexus.datom" ''
    Configure.Nexus.{ ${text nexus.sourceRoot} ${endpoint nexus.stableCodex} ${endpoint nexus.nextCodex} ${vector (map profile nexus.harnessProfiles)} ${vector nexus.metaAspects} ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.socket)
    } ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.binary)
    } ${text nexus.curriculumNexusPath} ${toString nexus.lease} ${
      option (if cfg.presentationPrompt == null then null else text cfg.presentationPrompt)
    } }
  '';
  sendServersQuery = pkgs.writeText "flow-048-send-servers.datom" ''
    Configure.SendServers.[ { ${text "${config.criomosHome.codexNextCandidate.package}/bin/codex"} ${text "${message}/bin/message-mcp-send"} } ]
  '';
  # One Configure each, in this order: the Nexus first, the investigation seat
  # after the metaflows it is launched from.
  #
  # FIXME(Mind core): Maintained is state, set by signal, never declared. Flow
  # 0.48 stores it inside the definition family: Continuity is a field of
  # ConfigureMetaflow (meta-signal-flow ethos/signal.ethos), and
  # Configure.Metaflows replaces that family whole, so this start-time
  # declaration resets every seat a signal moved. No signal sets Continuity
  # on one metaflow. Until Continuity is its own state family with its own
  # signal, every row of metaflows.datom is OnDemand.
  queries = [
    "${nexusQuery}"
    "${./flow-048/models.datom}"
    "${./flow-048/thresholds.datom}"
    "${./flow-048/leave-outs.datom}"
    "${sendServersQuery}"
    "${./flow-048/metaflows.datom}"
    "${./flow-048/harness-flags.datom}"
    "${./flow-048/investigation.datom}"
    "${./flow-048/default-minutes.datom}"
  ];
  # Runs before the Nexus starts, at every start, so the declared
  # configuration is in the store before any worker runs. `--configure-only`
  # opens the store, serves one Configure on the meta socket and exits, so
  # each query gets its own run. Configure replaces one family whole and
  # answers Unchanged when the store already holds the declaration, so a
  # repeat writes nothing. Arguments: the Start datom, the meta socket path,
  # then the query files.
  configure = pkgs.writeShellApplication {
    name = "configure-flow-048";
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
        reply=$(${runtime}/bin/flow-meta "{ «$socket» ''${body//${runtimeToken}/$XDG_RUNTIME_DIR} }") || true
        wait "$child"
        case "$reply" in
          Configured.Replaced|Configured.Unchanged) printf '%s %s\n' "$(basename "$query")" "$reply" ;;
          *) printf 'Flow Nexus 0.48 refused %s: %s\n' "$query" "$reply" >&2; exit 1 ;;
        esac
      done
    '';
  };
  # The 0.48 clients under versioned names, so the profile's flow and
  # flow-meta stay 0.44's.
  clients = pkgs.runCommand "flow-048-clients" { } ''
    mkdir -p $out/bin
    ln -s ${runtime}/bin/flow $out/bin/flow-048
    ln -s ${runtime}/bin/flow-meta $out/bin/flow-meta-048
  '';
  socketDirectory = "%t/${cfg.runtimeDirectory}";
  start = "{ «${socketDirectory}/flow.sock» «${socketDirectory}/flow-meta.sock» «%h/.local/state/${cfg.stateDirectory}/flow.sema» None }";
in
{
  options.criomosHome.flow048 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "flow-nexus-048";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-048";
      description = "Directory under ~/.local/state holding this Nexus's flow.sema.";
    };
    runtimeDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-048";
      description = "Directory under $XDG_RUNTIME_DIR holding this Nexus's flow.sock and flow-meta.sock.";
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
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion =
          cfg.stateDirectory != "flow-harnessflags" && cfg.runtimeDirectory != "flow-harnessflags";
        message = "Flow Nexus 0.48 must not open the 0.44 store or sockets";
      }
    ];
    home.packages = [ clients ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus 0.48";
        # The Nexus composes every launch's context through Curriculum
        # (ComposeStartup at Start, wake and resume); without it no flow starts.
        Requires = [ "curriculum-nexus.service" ];
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
        ExecStartPre = "${configure}/bin/configure-flow-048 ${lib.escapeShellArgs ([ start "${socketDirectory}/flow-meta.sock" ] ++ queries)}";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
