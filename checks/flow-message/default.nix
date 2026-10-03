{ inputs, pkgs, ... }:
# Regular Flow and Message on the user's own anchors; next off by default.
#
# Evaluation half: the regular units are flow-nexus, flow-configuration and
# message-nexus, on %t/flow/ and %t/message/, pinned to the regular inputs;
# turning next on adds the three next units on sockets and stores of their
# own, never a regular unit's.
#
# Runtime half: regular Flow, its configuration and regular Message start
# exactly as their units start them, on a fresh store; the regular CLIs
# (flow, flow-meta, message, message-meta) reach them by name.
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = "/build/h";
  runtime = "/build/run";

  expected = {
    flow = "636214e515f7c09d32ae614033224aa40944423f";
    message = "ce3eb6c65a0244672b34d8e91df2e840865d64e5";
  };

  stub = name: pkgs.writeShellScriptBin name "exit 0";
  moduleInputs = inputs // {
    herdr.packages.${system}.herdr = stub "herdr";
    harness.packages.${system}.default = stub "flow-id";
  };
  candidateCodex = stub "codex-next-flow-client";
  moduleConfig = nextEnable: {
    home.username = "li";
    home.homeDirectory = homeDirectory;
    xdg.stateHome = "${homeDirectory}/.local/state";
    criomos.corePackages = {
      codex = stub "codex";
      claude = stub "claude";
    };
    # This direct-module check has no Home module fixed point. Supply the
    # candidate contract that production receives from codex-next-candidate.
    criomosHome.codexNextCandidate = {
      hash = "candidatehash";
      clientPackage = candidateCodex;
    };
    criomosHome.flowMessage = {
      enable = true;
      next.enable = nextEnable;
    };
  };
  evaluate =
    nextEnable:
    let
      result = import ../../modules/home/profiles/min/flow-message.nix {
        inputs = moduleInputs;
        inherit lib pkgs;
        config = moduleConfig nextEnable;
        user.size = "Min";
      };
    in
    if result.config ? content then result.config.content else result.config;

  regular = evaluate false;
  withNext = evaluate true;

  units = regular.systemd.user.services;
  flowService = units.flow-nexus.Service;
  configure = units.flow-configuration;
  messageService = units.message-nexus.Service;
  legacyOverrideRetirement = regular.home.activation.retireLegacyFlowNexusOverride;
  nextUnitNames = lib.subtractLists (builtins.attrNames units) (
    builtins.attrNames withNext.systemd.user.services
  );

  flowPackage = inputs.flow.packages.${system}.default;
  messagePackage = inputs.message.packages.${system}.default;

  hasInfix = needle: text: lib.hasInfix (plain needle) (plain text);
  plain = builtins.unsafeDiscardStringContext;
  resolve = lib.replaceStrings [ "%t" ] [ runtime ];
in
assert inputs.flow.sourceInfo.rev == expected.flow;
assert inputs.message.sourceInfo.rev == expected.message;
# Regular units, under the regular names, and nothing next by default.
assert
  builtins.sort builtins.lessThan (builtins.attrNames units) == [
    "flow-configuration"
    "flow-nexus"
    "message-nexus"
  ];
assert
  builtins.sort builtins.lessThan nextUnitNames == [
    "flow-configuration-next"
    "flow-nexus-next"
    "message-nexus-next"
  ];
# Regular units run on the user's own anchors, with no arguments.
assert flowService.RuntimeDirectory == "flow";
assert messageService.RuntimeDirectory == "message";
assert flowService.ExecStart == "${flowPackage}/bin/flow-nexus";
assert messageService.ExecStart == "${messagePackage}/bin/message-nexus";
# PATH-first managed clients come from the exact regular Nexus packages.
assert regular.home.file.".local/bin/flow".source == "${flowPackage}/bin/flow";
assert regular.home.file.".local/bin/flow-meta".source == "${flowPackage}/bin/flow-meta";
assert regular.home.file.".local/bin/message".source == "${messagePackage}/bin/message";
assert regular.home.file.".local/bin/message-meta".source == "${messagePackage}/bin/message-meta";
assert !(builtins.any (line: lib.hasPrefix "HOME=" line || lib.hasPrefix "XDG_RUNTIME_DIR=" line) flowService.Environment);
assert !(messageService ? ExecStartPre);
assert messageService.Environment == [ ];
assert !(builtins.any (line: lib.hasPrefix "FLOW_" line) flowService.Environment);
# Regular Flow is configured on its own meta socket and admits regular Message.
assert configure.Unit.Requires == [ "flow-nexus.service" ];
assert configure.Service.Type == "oneshot";
assert hasInfix " %t/flow/flow-meta.sock " configure.Service.ExecStart;
assert hasInfix "Configure.{ %t/flow/flow.sock %t/flow/flow-meta.sock " configure.Service.ExecStart;
assert hasInfix "[ Psyche ] ${messagePackage}/bin/message-nexus }" configure.Service.ExecStart;
assert units.message-nexus.Unit.After == [ "flow-nexus.service" ];
# The known unmanaged 0.12.2 override is preserved before Home Manager reloads
# systemd; an unrecognized override must stop activation rather than shadowing
# the generated regular Flow service.
assert lib.elem "reloadSystemd" legacyOverrideRetirement.after;
assert lib.elem "linkGeneration" legacyOverrideRetirement.before;
assert hasInfix "refusing to retire an unrecognized flow-nexus override" legacyOverrideRetirement.data;
assert hasInfix "retired-overrides" legacyOverrideRetirement.data;
# Next, when on, stays on its own anchors.
assert withNext.systemd.user.services.flow-nexus-next.Service.RuntimeDirectory == "flow-next";
assert withNext.systemd.user.services.message-nexus-next.Service.RuntimeDirectory == "message-next";
pkgs.runCommand "flow-message"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    clients = lib.makeBinPath regular.home.packages;
  }
  ''
    set -eu
    run=${runtime}
    mkdir -p "$run" ${homeDirectory}
    pids=""
    cleanup() { for pid in $pids; do kill "$pid" 2>/dev/null || true; done; }
    trap cleanup EXIT

    wait_socket() {
      for _ in $(seq 300); do [ -S "$1" ] && return 0; sleep 0.05; done
      echo "socket $1 never appeared" >&2; exit 1
    }

    # Regular Flow, its configuration and regular Message exactly as their
    # units run them: real anchors, Flow first.
    mkdir -p "$run/flow" "$run/message"
    env -i HOME=${homeDirectory} XDG_RUNTIME_DIR="$run" \
      ${pkgs.coreutils}/bin/timeout 60 ${resolve flowService.ExecStart} &
    pids="$pids $!"
    wait_socket "$run/flow/flow-meta.sock"
    ${resolve configure.Service.ExecStart} | grep -F 'Configured.{'
    env -i HOME=${homeDirectory} XDG_RUNTIME_DIR="$run" \
      ${pkgs.coreutils}/bin/timeout 60 ${messageService.ExecStart} &
    pids="$pids $!"
    wait_socket "$run/message/message-owner.sock"

    for socket in flow/flow.sock flow/flow-meta.sock message/message.sock \
      message/message-owner.sock; do
      test -S "$run/$socket"
    done
    test -f ${homeDirectory}/.local/state/flow/flow.sema
    test -f ${homeDirectory}/.local/state/message/message.sema

    # The regular CLIs reach the regular Nexuses by name.
    export PATH="$clients:$PATH" XDG_RUNTIME_DIR="$run"
    for client in flow flow-meta message message-meta; do
      command -v "$client"
    done
    test "$(flow 'List.{}')" = 'Listed.[]'
    # Message's owner request resolves through Flow: with Flow there, an
    # unknown recipient is named; with no Flow it is MetaRefused.
    test "$(message-meta 'Send.{ [ 7d41e0 ] Soft Text.«probe» }')" = 'SendRejected.UnknownRecipient.7d41e0'
    test "$(message 'QueryReceipts.m-0000')" = 'MessageRejected.UnknownMessage'

    touch "$out"
  ''
