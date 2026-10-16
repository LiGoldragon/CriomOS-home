{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/flow-deployment { inherit inputs; };
  runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
  module = import ../../modules/home/profiles/min/flow.nix {
    inherit inputs pkgs;
    lib = pkgs.lib;
    user = { name = "li"; size = "Min"; };
    config = {
      home.username = "li";
      criomosHome.flow = { enable = true; package = runtime; };
    };
  };
  homeStart = module.config.content.systemd.user.services.flow-nexus.Service.ExecStart;
in
assert inputs.flow.sourceInfo.rev == "044f1af06871e37224331fdeae621b1174ca37dc";
assert !(inputs ? flow-next);
assert homeStart == "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-production/flow.sema }\"";
pkgs.runCommand "flow-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.python3
    ];
  }
  ''
    for name in flow flow-meta flow-nexus flow-hook; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    grep -F 'ExecStart=${runtime}/bin/flow-nexus ' ${deployment}/share/systemd/user/flow-nexus.service
    ${deployment}/bin/flow --version > cli-version
    ${deployment}/bin/flow-nexus --version > nexus-version
    test "$(cut -d ' ' -f 2 cli-version)" = "$(cut -d ' ' -f 2 nexus-version)"
    initializer=$(sed -n 's/^ExecStartPre=//p' ${deployment}/share/systemd/user/flow-nexus.service)
    grep -F '[ gpt-5.6-sol gpt-5.6-luna ]' "$initializer"
    if grep -F 'gpt-5.6-terra' "$initializer"; then
      echo "retired Terra capability in Flow initializer" >&2
      exit 1
    fi
    # A foreign store and stale socket must report the child's refusal,
    # never send the single Configure request to a dead socket.
    export HOME="$TMPDIR/refused-home"
    export XDG_RUNTIME_DIR="$TMPDIR/refused-runtime"
    mkdir -p "$HOME/.local/state/flow-production" "$XDG_RUNTIME_DIR/flow"
    printf 'foreign-store-preserve' > "$HOME/.local/state/flow-production/flow.sema"
    cp "$HOME/.local/state/flow-production/flow.sema" foreign-before
    python -c 'import os,socket; s=socket.socket(socket.AF_UNIX); s.bind(os.environ["XDG_RUNTIME_DIR"]+"/flow/flow-meta.sock"); s.close()'
    if "$initializer" > refused.log 2>&1; then
      echo "initializer accepted a foreign store" >&2
      exit 1
    fi
    grep -F 'Flow configuration child exited before socket readiness' refused.log
    ! grep -F 'Connection refused' refused.log
    cmp foreign-before "$HOME/.local/state/flow-production/flow.sema"

    # A real configure-only child must become ready and consume exactly its
    # Configure request; no readiness connection is sent by the initializer.
    export HOME="$TMPDIR/accepted-home"
    export XDG_RUNTIME_DIR="$TMPDIR/accepted-runtime"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    "$initializer" > accepted.log 2>&1
    grep -Fx 'Configured' accepted.log
    mkdir -p "$out"
    cp cli-version nexus-version "$out/"
  ''
