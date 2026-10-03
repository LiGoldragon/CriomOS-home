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
  cfg = config.criomosHome.flowMessage;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = config.home.homeDirectory;
  legacyFlowOverride = "${config.xdg.configHome}/systemd/user/flow-nexus.service.d/override.conf";
  legacyFlowOverrideContents = pkgs.writeText "flow-nexus-0.12.2-override" ''
    [Service]
    ExecStart=
    ExecStart=/nix/store/c044v5pa2qh4xcjkbiqiqb9qax6l36bd-flow-0.12.2/bin/flow-nexus
  '';
  retiredFlowOverridesDirectory = "${config.xdg.stateHome}/flow/retired-overrides";

  # Flow and Message as stable/next pairs. Stable is the regular pair: Flow
  # 0.23.0 and Message 0.19.0, which move together (shared signal-flow and
  # meta-signal-flow), on the user's own anchors (sockets under
  # %t/flow/ and %t/message/, stores under ~/.local/state/{flow,message}/).
  # Next shares the staged Flow/Message revision for this deployment and runs
  # beside stable on anchors of its own.  A later staged revision may move its
  # inputs ahead of stable's without changing either slot's anchors.
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

  # The Flow Nexus unit, for either slot. The Codex servers and the
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
  # Flow takes MetaAspects and MessageNexusPath only through one meta
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

  # The Message Nexus unit, for either slot: no arguments; its store and
  # sockets follow from its anchors, and Flow's sockets from the same slot.
  # Stable Message finds stable Flow at %t/flow/ directly; next Message has
  # next Flow's socket directory linked into its anchor before start.
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
      ExecStart = "${messageInstance.package}/bin/message-nexus";
      Restart = "on-failure";
      RestartSec = "2s";
    }
    // lib.optionalAttrs (messageInstance.slot == "next") {
      ExecStartPre = "${messageInstance.peerLinks} %t";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # The three units of one slot, under that slot's names.
  slotUnits = flowInstance: messageInstance: {
    ${flowInstance.serviceUnit} = flowNexusUnit flowInstance;
    ${flowInstance.unitName "flow-configuration"} = flowConfigurationUnit flowInstance messageInstance;
    ${messageInstance.serviceUnit} = messageNexusUnit messageInstance flowInstance;
  };
in
{
  options.criomosHome.flowMessage = {
    enable = mkOption {
      type = bool;
      default = config.home.username == "li";
      description = "Run the regular Flow and Message Nexuses (flow-nexus, flow-configuration, message-nexus) on the user's own sockets and stores.";
    };
    next.enable = mkOption {
      type = bool;
      default = config.home.username == "li";
      description = "Run the staged next Flow and next Message beside the regular pair, on sockets and stores of their own.";
    };
  };

  config = mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = config.home.username == "li";
        message = "Flow uses li's workspace and Codex homes; it cannot be enabled for another user";
      }
    ];

    home.packages = [
      flow.stable.clients
      message.stable.clients
    ]
    ++ lib.optionals cfg.next.enable [
      flow.next.clients
      message.next.clients
    ];

    # The inherited user profile can retain an older client. These managed
    # PATH-first links select the exact packages that run the regular pair.
    home.file = {
      ".local/bin/flow".source = "${flow.stable.package}/bin/flow";
      ".local/bin/flow-meta".source = "${flow.stable.package}/bin/flow-meta";
      ".local/bin/message".source = "${message.stable.package}/bin/message";
      ".local/bin/message-meta".source = "${message.stable.package}/bin/message-meta";
    };

    # The previous unmanaged drop-in replaces the generated regular Flow
    # ExecStart with 0.12.2.  Preserve only that exact stale byte sequence in
    # Flow's recovery state before Home Manager reloads systemd; any other
    # user-owned override remains a hard activation refusal.
    home.activation.retireLegacyFlowNexusOverride =
      lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
        set -eu

        override_path=${lib.escapeShellArg legacyFlowOverride}
        expected_override=${lib.escapeShellArg legacyFlowOverrideContents}
        retired_directory=${lib.escapeShellArg retiredFlowOverridesDirectory}
        retired_override="$retired_directory/flow-nexus-0.12.2.override.conf"

        if [ ! -e "$override_path" ] && [ ! -L "$override_path" ]; then
          exit 0
        fi
        if [ -L "$override_path" ] || ! ${pkgs.diffutils}/bin/cmp -s "$override_path" "$expected_override"; then
          echo "refusing to retire an unrecognized flow-nexus override: $override_path" >&2
          exit 1
        fi
        if [ -e "$retired_override" ] || [ -L "$retired_override" ]; then
          echo "refusing to overwrite preserved flow-nexus override: $retired_override" >&2
          exit 1
        fi

        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$retired_directory"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$override_path" "$retired_override"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rmdir --ignore-fail-on-non-empty "$( ${pkgs.coreutils}/bin/dirname "$override_path" )"
      '';

    systemd.user.services =
      slotUnits flow.stable message.stable
      // lib.optionalAttrs cfg.next.enable (slotUnits flow.next message.next);
  };
}
