{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  homeDirectory = "/build/message-flow-wiring-home";
  stateHome = "${homeDirectory}/.local/state";

  messagePackage = inputs.message.packages.${system}.default;
  flowPackage = inputs.flow.packages.${system}.default;

  messageResult = import ../../modules/home/profiles/min/message.nix {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      home.username = "message-flow-test-user";
      xdg.stateHome = stateHome;
      criomosHome.message.enable = true;
    };
    user.size = "Min";
  };
  flowResult = import ../../modules/home/profiles/min/flow.nix {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      home.username = "message-flow-test-user";
      criomosHome.flow.enable = true;
    };
  };

  configuration = result: if result.config ? content then result.config.content else result.config;
  messageConfiguration = configuration messageResult;
  flowConfiguration = configuration flowResult;
  messageUnit = messageConfiguration.systemd.user.services.message-daemon;
  flowUnit = flowConfiguration.systemd.user.services.flow-nexus;
  messageProfile = lib.head messageConfiguration.home.packages;
  flowProfile = lib.head flowConfiguration.home.packages;
  componentRouteChecks = [
    inputs.message.checks.${system}.message-herdr-route-submits-canonical-datom-once
    inputs.message.checks.${system}.message-herdr-route-refuses-unready-composers
    inputs.message.checks.${system}.message-stale-herdr-route-never-falls-back-to-native
    inputs.message.checks.${system}.message-native-only-direct-protocol-remains-routable
    inputs.message.checks.${system}.message-herdr-uncertain-delivery-is-durable-without-retry
    inputs.flow.checks.${system}.flow-v5-row-preservation
    inputs.flow.checks.${system}.flow-herdr-route-durability
    inputs.flow.checks.${system}.flow-stale-route-unavailable
    inputs.flow.checks.${system}.flow-conflicting-registration-refusal
    inputs.flow.checks.${system}.flow-herdr-registration-binding
    inputs.flow.checks.${system}.flow-native-resolution-serialization
  ];
in
assert messagePackage.version == "0.12.0";
assert flowPackage.version == "0.3.0";
assert messageUnit.Unit.After == [ "flow-nexus.service" ];
assert messageUnit.Unit.Requires == [ "flow-nexus.service" ];
assert messageUnit.Service.Environment == [ "FLOW_SOCKET=%t/flow/flow.sock" ];
assert
  messageUnit.Service.ExecStart
  == "${messagePackage}/bin/message-nexus ${stateHome}/message/message-daemon.rkyv";
assert flowUnit.Service.ExecStart == "${flowPackage}/bin/flow-nexus";
assert flowUnit.Service.RuntimeDirectory == "flow";
pkgs.runCommand "message-flow-wiring"
  {
    inherit componentRouteChecks;
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    set -eu

    for component_check in $componentRouteChecks; do
      test -e "$component_check"
    done

    test -x '${messageProfile}/bin/message'
    test -x '${messageProfile}/bin/message-meta'
    test -x '${messageProfile}/bin/meta-message'
    test -x '${flowProfile}/bin/flow'
    test -x '${flowProfile}/bin/flow-meta'

    test "$(readlink '${messageProfile}/bin/meta-message')" = message-meta

    cat >capture-frame.py <<'PY'
    import pathlib
    import socket
    import sys

    socket_path = pathlib.Path(sys.argv[1])
    receipt_path = pathlib.Path(sys.argv[2])
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(socket_path))
    listener.listen(1)
    listener.settimeout(10)
    receipt_path.with_suffix(".ready").touch()
    peer, _ = listener.accept()
    with peer:
        header = peer.recv(4)
        if len(header) != 4:
            raise RuntimeError("client did not write a complete frame header")
        remaining = int.from_bytes(header, byteorder="big")
        frame = bytearray()
        while len(frame) < remaining:
            chunk = peer.recv(remaining - len(frame))
            if not chunk:
                raise RuntimeError("client closed before writing its frame")
            frame.extend(chunk)
    if not frame:
        raise RuntimeError("client wrote an empty typed frame")
    receipt_path.write_text(f"{len(frame)}\n")
    PY

    capture_frame() {
      socket_path="$1"
      receipt="$2"
      shift 2
      mkdir -p "$(dirname "$socket_path")"
      python3 capture-frame.py "$socket_path" "$receipt" &
      server_pid=$!
      ready="''${receipt%.*}.ready"
      for _ in $(seq 1 100); do
        test -e "$ready" && break
        sleep 0.01
      done
      test -e "$ready"
      if "$@" >"$receipt.stdout" 2>"$receipt.stderr"; then
        echo 'client unexpectedly accepted an absent reply' >&2
        exit 1
      fi
      wait "$server_pid"
      test "$(cat "$receipt")" -gt 0
    }

    runtime="$PWD/runtime"
    export XDG_RUNTIME_DIR="$runtime"
    capture_frame "$runtime/message/message.sock" message.frame \
      '${messageProfile}/bin/message' QueryAgentRegistry.All
    capture_frame "$runtime/message/message-owner.sock" message-meta.frame \
      '${messageProfile}/bin/message-meta' \
      "Configure.{ $runtime/message/message.sock 384 $runtime/message/message-owner.sock 384 $runtime/router/router.sock [] UnixUser.1001 }"
    capture_frame "$runtime/flow/flow.sock" flow.frame \
      '${flowProfile}/bin/flow' resolve test-flow
    capture_frame "$runtime/flow/flow-meta.sock" flow-meta.frame \
      '${flowProfile}/bin/flow-meta' configure \
      "$runtime/flow/flow.sock" "$runtime/flow/flow-meta.sock"

    touch "$out"
  ''
