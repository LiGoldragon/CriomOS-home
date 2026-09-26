{ inputs, pkgs, ... }:
# Next Flow and next Message run beside the stable pair without touching it.
#
# Evaluation half: the stable modules are the oracle for what stable owns
# (unit names, runtime directories, socket and store paths); every next
# counterpart must differ, and the pins must be the ones named here.
#
# Runtime half: stable Flow 0.14 and next Flow 0.16 run side by side in one
# runtime directory, next Message beside them, each started exactly as its
# unit starts it; the next CLIs reach only the next sockets.
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = "/build/h";
  runtime = "/build/run";

  expected = {
    stableFlow = "9fcd625ac7a0d44be58b9d365a94064e91f09219";
    stableMessage = "930c5169ffcf5fa3784b34b2751763009e926d1d";
    nextFlow = "9aa9bf88e3ff6f3b68864eb300ee009897162ef4";
    nextMessage = "f1843dbaa63f38634dc10d3b28df2f4a482d6d35";
  };

  stub = name: pkgs.writeShellScriptBin name "exit 0";
  moduleInputs = inputs // {
    herdr.packages.${system}.herdr = stub "herdr";
    harness.packages.${system}.default = stub "flow-id";
  };
  moduleConfig = {
    home.username = "li";
    home.homeDirectory = homeDirectory;
    xdg.stateHome = "${homeDirectory}/.local/state";
    criomos.corePackages = {
      codex = stub "codex";
      claude = stub "claude";
    };
    criomosHome.flow = {
      enable = true;
      package = inputs.flow.packages.${system}.default;
    };
    criomosHome.message.enable = true;
    criomosHome.flowMessageNext.enable = true;
  };
  evaluate =
    file:
    let
      result = import file {
        inputs = moduleInputs;
        inherit lib pkgs;
        config = moduleConfig;
        user.size = "Min";
      };
    in
    if result.config ? content then result.config.content else result.config;

  next = evaluate ../../modules/home/profiles/min/flow-message-next.nix;
  stableFlow = evaluate ../../modules/home/profiles/min/flow.nix;
  stableMessage = evaluate ../../modules/home/profiles/min/message.nix;

  nextUnits = next.systemd.user.services;
  stableUnitNames =
    builtins.attrNames stableFlow.systemd.user.services
    ++ builtins.attrNames stableMessage.systemd.user.services;
  flowNext = nextUnits.flow-nexus-next.Service;
  configureNext = nextUnits.flow-configuration-next;
  messageNext = nextUnits.message-nexus-next.Service;
  stableFlowService = stableFlow.systemd.user.services.flow-nexus.content.Service;
  stableMessageService = stableMessage.systemd.user.services.message-daemon.Service;

  flowNextPackage = inputs.flow-next.packages.${system}.default;
  messageNextPackage = inputs.message-next.packages.${system}.default;

  # Stable's sockets as stable itself names them: Flow's under its
  # RuntimeDirectory at the Nexus defaults, Message's in its writer request.
  stableSockets = [
    "%t/${stableFlowService.RuntimeDirectory}/flow.sock"
    "%t/${stableFlowService.RuntimeDirectory}/flow-meta.sock"
    "%t/message/message.sock"
    "%t/message/message-owner.sock"
  ];
  nextSockets = [
    "%t/flow-next/flow/flow.sock"
    "%t/flow-next/flow/flow-meta.sock"
    "%t/message-next/message/message.sock"
    "%t/message-next/message/message-owner.sock"
  ];

  # A unit's command or environment as the sandbox runs it: systemd's %t is
  # the sandbox runtime directory.
  # Substring tests compare text; store-path context is not part of it.
  hasInfix = needle: text: lib.hasInfix (plain needle) (plain text);
  hasPrefix = needle: text: lib.hasPrefix (plain needle) (plain text);
  plain = builtins.unsafeDiscardStringContext;
  resolve = lib.replaceStrings [ "%t" ] [ runtime ];
  environment = service: lib.concatMapStringsSep " " (line: lib.escapeShellArg (resolve line)) service.Environment;
in
assert inputs.flow.sourceInfo.rev == expected.stableFlow;
assert inputs.message.sourceInfo.rev == expected.stableMessage;
assert inputs.flow-next.sourceInfo.rev == expected.nextFlow;
assert inputs.message-next.sourceInfo.rev == expected.nextMessage;
# Next units exist, under their own names, none of them a stable unit's.
assert
  builtins.sort builtins.lessThan (builtins.attrNames nextUnits) == [
    "flow-configuration-next"
    "flow-nexus-next"
    "message-nexus-next"
  ];
assert builtins.all (name: !(builtins.elem name stableUnitNames)) (builtins.attrNames nextUnits);
# Runtime directories are disjoint: stable owns flow and message.
assert stableFlowService.RuntimeDirectory == "flow";
assert stableMessageService.RuntimeDirectory == "message";
assert flowNext.RuntimeDirectory == "flow-next";
assert messageNext.RuntimeDirectory == "message-next";
# Sockets are pairwise distinct across both slots.
assert hasInfix "%t/message/message.sock %t/message/message-owner.sock" (lib.last stableMessageService.ExecStartPre);
assert builtins.length (lib.unique (stableSockets ++ nextSockets)) == 8;
# Next runs the pinned 0.16 executables with no arguments, on its anchors.
assert flowNext.ExecStart == "${flowNextPackage}/bin/flow-nexus";
assert messageNext.ExecStart == "${messageNextPackage}/bin/message-nexus";
assert builtins.elem "HOME=${homeDirectory}/.local/state/flow-next" flowNext.Environment;
assert builtins.elem "XDG_RUNTIME_DIR=%t/flow-next" flowNext.Environment;
assert builtins.elem "HOME=${homeDirectory}/.local/state/message-next" messageNext.Environment;
assert builtins.elem "XDG_RUNTIME_DIR=%t/message-next" messageNext.Environment;
# Next Flow admits next Message, and is configured on its own meta socket.
assert configureNext.Unit.Requires == [ "flow-nexus-next.service" ];
assert configureNext.Service.Type == "oneshot";
assert hasInfix " %t/flow-next/flow/flow-meta.sock " configureNext.Service.ExecStart;
assert hasInfix "Configure.{ %t/flow-next/flow/flow.sock %t/flow-next/flow/flow-meta.sock " configureNext.Service.ExecStart;
assert hasInfix "[ Psyche ] ${messageNextPackage}/bin/message-nexus }" configureNext.Service.ExecStart;
assert nextUnits.message-nexus-next.Unit.After == [ "flow-nexus-next.service" ];
# The stable units are the stable modules' own, pinned to stable packages.
assert stableFlowService.ExecStart == "${inputs.flow.packages.${system}.default}/bin/flow-nexus";
assert hasPrefix "${inputs.message.packages.${system}.default}/bin/message-daemon " stableMessageService.ExecStart;
pkgs.runCommand "flow-message-next"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    clients = lib.makeBinPath next.home.packages;
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

    # Stable Flow exactly as its unit runs it: real anchors.
    mkdir -p "$run/${stableFlowService.RuntimeDirectory}"
    env -i HOME=${homeDirectory} XDG_RUNTIME_DIR="$run" \
      ${pkgs.coreutils}/bin/timeout 60 ${resolve stableFlowService.ExecStart} &
    pids="$pids $!"
    wait_socket "$run/flow/flow-meta.sock"

    # Next Flow and next Message exactly as their units run them.
    mkdir -p "$run/flow-next" "$run/message-next"
    env -i ${environment flowNext} ${pkgs.coreutils}/bin/timeout 60 ${flowNext.ExecStart} &
    pids="$pids $!"
    wait_socket "$run/flow-next/flow/flow-meta.sock"
    ${resolve configureNext.Service.ExecStart} | grep -F 'Configured.{'
    ${resolve messageNext.ExecStartPre}
    env -i ${environment messageNext} ${pkgs.coreutils}/bin/timeout 60 ${messageNext.ExecStart} &
    pids="$pids $!"
    wait_socket "$run/message-next/message/message-owner.sock"

    # Stable and next listen side by side; nothing next landed in stable's
    # runtime directory or store.
    for socket in flow/flow.sock flow/flow-meta.sock flow-next/flow/flow.sock \
      flow-next/flow/flow-meta.sock message-next/message/message.sock \
      message-next/message/message-owner.sock; do
      test -S "$run/$socket"
    done
    test "$(ls "$run/flow")" = "$(printf 'flow-meta.sock\nflow.sock')"
    test ! -e "$run/message"
    test -f ${homeDirectory}/.local/state/flow-next/.local/state/flow/flow.sema
    test -f ${homeDirectory}/.local/state/message-next/.local/state/message/message.sema
    test ! -e ${homeDirectory}/.local/state/message

    # The next CLIs reach the next Nexuses by name.
    export PATH="$clients:$PATH" XDG_RUNTIME_DIR="$run"
    for client in flow-next flow-next-meta message-next message-next-meta; do
      command -v "$client"
    done
    test "$(flow-next 'List.{}')" = 'Listed.[]'
    # Next Message's owner request resolves through next Flow: with Flow
    # there, an unknown recipient is named; with no Flow it is MetaRefused.
    test "$(message-next-meta 'Send.{ [ 7d41e0 ] Soft Text.«probe» }')" = 'SendRejected.UnknownRecipient.7d41e0'
    test "$(message-next 'QueryReceipts.m-0000')" = 'MessageRejected.UnknownMessage'

    touch "$out"
  ''
