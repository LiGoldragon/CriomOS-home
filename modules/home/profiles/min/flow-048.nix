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
  system = pkgs.stdenv.hostPlatform.system;
  home = config.home.homeDirectory;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  pathOnly = builtins.unsafeDiscardStringContext;
  nextCodexHome = "${home}/.codex-next-${config.criomosHome.codexNextCandidate.hash}";
  message = inputs.message.packages.${system}.default;
  # The Nexus a store is configured with, as data. The build bakes the part
  # mkFlowPackage takes into the executable, for a new store to open with;
  # the configure step below declares it whole over the meta socket.
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
    curriculumNexusPath = "${cfg.curriculumRuntimeDirectory}/curriculum/curriculum.sock";
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
      runtimeDirectory = cfg.curriculumRuntimeDirectory;
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
  # ConfigureNexus at meta-signal-flow 6519765, the shape flow-048's pin
  # reads. The presentation prompt joins it with the delivery commit.
  nexusQuery = pkgs.writeText "flow-048-nexus.datom" ''
    Configure.Nexus.{ ${text nexus.sourceRoot} ${endpoint nexus.stableCodex} ${endpoint nexus.nextCodex} ${vector (map profile nexus.harnessProfiles)} ${vector nexus.metaAspects} ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.socket)
    } ${
      option (if cfg.messageNexus == null then null else text cfg.messageNexus.binary)
    } ${text nexus.curriculumNexusPath} ${toString nexus.lease} }
  '';
  sendServersQuery = pkgs.writeText "flow-048-send-servers.datom" ''
    Configure.SendServers.[ { ${text "${config.criomosHome.codexNextCandidate.package}/bin/codex"} ${text "${message}/bin/message-mcp-send"} } ]
  '';
  # One Configure each, in this order: the Nexus first, the investigation seat
  # after the metaflows it is launched from.
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
  # Runs after the Nexus is up, at every start. Configure replaces one family
  # whole and answers Unchanged when the store already holds the declaration,
  # so a repeat writes nothing.
  configure = pkgs.writeShellApplication {
    name = "configure-flow-048";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      socket="$1"
      shift
      meta() { ${runtime}/bin/flow-meta "{ «$socket» $1 }"; }
      ready=false
      for _attempt in $(seq 1 300); do
        case "$(meta Configuration 2>/dev/null)" in
          Configuration.*|Unconfigured) ready=true; break ;;
        esac
        sleep 0.1
      done
      if ! "$ready"; then
        echo "Flow Nexus 0.48 meta socket did not answer Configuration" >&2
        exit 1
      fi
      for query in "$@"; do
        reply=$(meta "$(cat "$query")")
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
    curriculumRuntimeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1001";
      description = "Runtime directory whose curriculum/curriculum.sock a new store reaches Curriculum at.";
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
        socket = "${cfg.curriculumRuntimeDirectory}/message/message.sock";
        binary = "${message}/bin/message-nexus";
      };
      description = "The Message Nexus this Nexus admits as a meta peer; null admits none.";
    };
    presentationPrompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Text the Psyche core Primary system prompt carries; null carries none. Waits on the flow delivery commit, whose ConfigureNexus gains Option<PresentationPrompt.String>.";
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
      {
        # Waiting on the delivery commit: flow-048's pin has no
        # PresentationPrompt in ConfigureNexus to carry a value.
        assertion = cfg.presentationPrompt == null;
        message = "criomosHome.flow048.presentationPrompt waits on the flow delivery commit";
      }
    ];
    home.packages = [ clients ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus 0.48";
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
        ExecStartPost = "${configure}/bin/configure-flow-048 ${socketDirectory}/flow-meta.sock ${lib.escapeShellArgs queries}";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
