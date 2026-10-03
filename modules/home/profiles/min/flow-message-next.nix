{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  stableNext = import ../../../../lib/stable-next-service.nix { inherit lib pkgs; };
  cfg = config.criomosHome.flowMessageNext;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = config.home.homeDirectory;

  # Flow and Message as stable/next pairs. Stable is the pair the Home line
  # already runs (profiles/min/flow.nix and message.nix, untouched); next is
  # Flow 0.23.0 and Message 0.19.0, which must move together (shared
  # signal-flow and meta-signal-flow), on anchors of their own.
  flow = stableNext.pair {
    name = "flow";
    unit = "flow-nexus";
    inherit homeDirectory;
    stablePackage = inputs.flow.packages.${system}.default;
    nextPackage = inputs.flow-next.packages.${system}.default;
    sockets = {
      ordinary = {
        file = "flow.sock";
        variable = "FLOW_SOCKET";
        client = "flow";
      };
      meta = {
        file = "flow-meta.sock";
        variable = "FLOW_META_SOCKET";
        client = "flow-meta";
      };
    };
  };
  message = stableNext.pair {
    name = "message";
    unit = "message-nexus";
    inherit homeDirectory;
    stablePackage = inputs.message.packages.${system}.default;
    nextPackage = inputs.message-next.packages.${system}.default;
    # Message finds Flow at `$XDG_RUNTIME_DIR/flow/`; next Message finds next
    # Flow there.
    nextPeers.flow = flow.next;
    sockets = {
      ordinary = {
        file = "message.sock";
        variable = "MESSAGE_SOCKET";
        client = "message";
      };
      meta = {
        file = "message-owner.sock";
        variable = "MESSAGE_META_SOCKET";
        client = "message-meta";
      };
    };
  };

  stableCodexClient =
    config.criomosHome.herdr.stableCodexClientPackage or config.criomos.corePackages.codex;
  nextCodexClient =
    config.criomosHome.codexNextCandidate.clientPackage or config.criomos.corePackages.codex;
  flowRuntimePath = lib.makeBinPath [
    (config.criomosHome.herdr.package or inputs.herdr.packages.${system}.herdr)
    inputs.harness.packages.${system}.default
    config.criomos.corePackages.codex
    config.criomos.corePackages.claude
  ];
  stableModels = [
    "gpt-5.6-terra"
    "gpt-5.6-sol"
    "gpt-5.6-luna"
  ];
  nextModels = [
    "gpt-6-sol"
    "gpt-6-luna"
    "gpt-6-astra"
  ];
  codex = {
    stable = {
      client = "${stableCodexClient}/bin/codex-stable-flow-client";
      home = "${homeDirectory}/.codex-next";
      models = stableModels;
    };
    next = {
      client = "${nextCodexClient}/bin/codex-next-flow-client";
      home = "${homeDirectory}/.codex-next-${config.criomosHome.codexNextCandidate.hash}";
      models = nextModels;
    };
  };
  codexSocket = endpoint: "${endpoint.home}/app-server-control/app-server-control.sock";

  # The Flow 0.16–0.17 Nexus unit, for either slot. The Codex servers and the
  # workspace are the user's own whichever slot runs: both Flows observe the
  # same Herdr and launch through the same Codex servers.
  flowNexusUnit = instance: {
    Unit = {
      Description = "Flow Nexus (${instance.slot})";
      After = [ "codex-remote-control.service" ];
      Requires = [ "codex-remote-control.service" ];
    };
    Service = {
      Type = "simple";
      RuntimeDirectory = instance.runtimeDirectory;
      RuntimeDirectoryMode = "0700";
      Environment = instance.anchorEnvironment ++ [
        "CLAUDE_CONFIG_DIR=${homeDirectory}/.claude"
        "CODEX_HOME=${codex.stable.home}"
        "PATH=${flowRuntimePath}"
      ];
      ExecStart = "${instance.package}/bin/flow-nexus";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
  occupiedNextFlowUnit = {
    Unit = {
      Description = "Flow Nexus (next)";
      After = [ "codex-remote-control.service" ];
      Requires = [ "codex-remote-control.service" ];
    };
    Service = {
      Type = "simple";
      RuntimeDirectory = "flow-next";
      RuntimeDirectoryMode = "0700";
      Environment = [
        "HOME=/home/li/.local/state/flow-next"
        "XDG_RUNTIME_DIR=%t/flow-next"
        "XDG_CONFIG_HOME=/home/li/.config"
        "XDG_DATA_HOME=/home/li/.local/share"
        "XDG_STATE_HOME=/home/li/.local/state"
        "XDG_CACHE_HOME=/home/li/.cache"
        "CLAUDE_CONFIG_DIR=/home/li/.claude"
        "CODEX_HOME=/home/li/.codex"
        "FLOW_SOURCE_ROOT=/home/li/primary"
        "FLOW_CODEX_STABLE_CLIENT=/nix/store/0s199vn7jivakb7kqkcc2znxw4klv840-codex-stable-flow-client/bin/codex-stable-flow-client"
        "FLOW_CODEX_STABLE_SOCKET=/home/li/.codex/app-server-control/app-server-control.sock"
        "FLOW_CODEX_STABLE_HOME=/home/li/.codex"
        "FLOW_CODEX_STABLE_MODELS=gpt-5.6-terra,gpt-5.6-sol,gpt-5.6-luna"
        "FLOW_CODEX_NEXT_CLIENT=/nix/store/x74szg3cbsn5s41nan43kfs6wb4xww61-codex-next-flow-client/bin/codex-next-flow-client"
        "FLOW_CODEX_NEXT_SOCKET=/home/li/.codex-next/app-server-control/app-server-control.sock"
        "FLOW_CODEX_NEXT_HOME=/home/li/.codex-next"
        "FLOW_CODEX_NEXT_MODELS=gpt-6-sol,gpt-6-luna,gpt-6-astra"
        "PATH=/nix/store/9x03bz0q0a978zrzcshrlmmb4fvcmdb6-herdr-0.8.2/bin:/nix/store/b4wzlwmzbfis6ys2b1svh531dplxxyd3-harness-0.3.4/bin:/nix/store/wdj0sc69r4n9is1idfb32vcx5739ijkh-codex-0.153.4/bin:/nix/store/qsq3lh2i05dz77dakipwy9f1fkssq1zw-claude-code-2.1.284/bin"
      ];
      ExecStart = "/nix/store/7z15aqi46rk73v0ahaaazg6nq1hb0vjc-flow-0.17.4/bin/flow-nexus";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
  # This oneshot configures the already-running next Flow over its meta socket.
  # Replacing it would reconfigure that process during activation, so retain the
  # exact installed payload while its existing sessions are protected.
  occupiedNextFlowConfigurationUnit = {
    Unit = {
      Description = "Flow Nexus configuration (next) — MetaAspects and the admitted Message Nexus";
      After = [ "flow-nexus-next.service" ];
      Requires = [ "flow-nexus-next.service" ];
      PartOf = [ "flow-nexus-next.service" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/nix/store/5fg9dagqyfb2cwgjh79hkkhyn90142b6-flow-configure-next %t/flow-next/flow/flow-meta.sock 'Configure.{ %t/flow-next/flow/flow.sock %t/flow-next/flow/flow-meta.sock /home/li/primary { /nix/store/0s199vn7jivakb7kqkcc2znxw4klv840-codex-stable-flow-client/bin/codex-stable-flow-client /home/li/.codex /home/li/.codex/app-server-control/app-server-control.sock [ gpt-5.6-terra gpt-5.6-sol gpt-5.6-luna ] } { /nix/store/x74szg3cbsn5s41nan43kfs6wb4xww61-codex-next-flow-client/bin/codex-next-flow-client /home/li/.codex-next /home/li/.codex-next/app-server-control/app-server-control.sock [ gpt-6-sol gpt-6-luna gpt-6-astra ] } [ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ] [ Psyche ] /nix/store/3v8qs8h4ydmcrjjw29arzb0qk9qxqicq-message-0.17.0/bin/message-nexus }'";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Flow 0.16–0.17 takes MetaAspects and MessageNexusPath only through one meta
  # `Configure`, which replaces the record whole, so every field is stated.
  # The Message Nexus it admits is the one of the same slot.
  codexEndpointDatom =
    endpoint:
    "{ ${endpoint.client} ${endpoint.home} ${codexSocket endpoint} [ ${lib.concatStringsSep " " endpoint.models} ] }";
  configureDatom =
    flowInstance: messageInstance:
    lib.concatStringsSep " " [
      "Configure.{"
      flowInstance.socket.ordinary
      flowInstance.socket.meta
      "${homeDirectory}/primary"
      (codexEndpointDatom codex.stable)
      (codexEndpointDatom codex.next)
      "[ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ]"
      "[ Psyche ]"
      "${messageInstance.package}/bin/message-nexus"
      "}"
    ];
  # The Nexus is Type=simple; the request waits for its meta socket, bounded
  # so a Nexus that never listens fails this unit instead of hanging it.
  configureScript =
    flowInstance:
    pkgs.writeShellScript "${flowInstance.unitName "flow-configure"}" ''
      set -eu
      socket="$1"
      shift
      attempt=0
      while [ ! -S "$socket" ]; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 300 ]; then
          echo "flow-configure: $socket never appeared" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      reply="$(FLOW_META_SOCKET="$socket" ${flowInstance.package}/bin/flow-meta "$@")"
      echo "$reply"
      case "$reply" in
        Configured.*) exit 0 ;;
        *) echo "flow-configure: Flow refused the configuration" >&2; exit 1 ;;
      esac
    '';
  flowConfigurationUnit = flowInstance: messageInstance: {
    Unit = {
      Description = "Flow Nexus configuration (${flowInstance.slot}) — MetaAspects and the admitted Message Nexus";
      After = [ "${flowInstance.serviceUnit}.service" ];
      Requires = [ "${flowInstance.serviceUnit}.service" ];
      PartOf = [ "${flowInstance.serviceUnit}.service" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${configureScript flowInstance} ${flowInstance.socket.meta} ${lib.escapeShellArg (configureDatom flowInstance messageInstance)}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # The Message 0.16–0.17 Nexus unit, for either slot: no arguments; its store and
  # sockets follow from its anchors, and Flow's sockets from the same slot.
  messageNexusUnit = messageInstance: flowInstance: {
    Unit = {
      Description = "Message Nexus (${messageInstance.slot}) — durable message ledger";
      After = [ "${flowInstance.serviceUnit}.service" ];
      Wants = [ "${flowInstance.serviceUnit}.service" ];
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "simple";
      RuntimeDirectory = messageInstance.runtimeDirectory;
      RuntimeDirectoryMode = "0700";
      Environment = messageInstance.anchorEnvironment;
      ExecStartPre = "${messageInstance.peerLinks} %t";
      ExecStart = "${messageInstance.package}/bin/message-nexus";
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
{
  options.criomosHome.flowMessageNext = {
    enable = mkOption {
      type = bool;
      default = config.home.username == "li";
      description = "Run next Flow and next Message beside the stable pair, on their own sockets and stores.";
    };
  };

  config = mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = config.home.username == "li";
        message = "next Flow uses li's workspace and Codex homes; it cannot be enabled for another user";
      }
    ];

    home.packages = [
      flow.next.clients
      message.next.clients
    ];

    systemd.user.services = {
      ${flow.next.serviceUnit} = flowNexusUnit flow.next;
      ${flow.next.unitName "flow-configuration"} = flowConfigurationUnit flow.next message.next;
      ${message.next.serviceUnit} = messageNexusUnit message.next flow.next;
    };
  };
}
