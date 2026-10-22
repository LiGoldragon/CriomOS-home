{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/flow-deployment { inherit inputs; };
  runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
  module = import ../../modules/home/profiles/min/flow.nix {
    inherit inputs pkgs;
    lib = pkgs.lib;
    user = {
      name = "li";
      size = "Min";
    };
    config = {
      home.username = "li";
      criomosHome.flow = {
        enable = true;
        package = runtime;
        stateDirectory = "flow-03521";
        solModel = "gpt-6.1-sol";
        landingRepository = null;
        landingDeployRequest = null;
      };
    };
  };
  service = module.config.content.systemd.user.services.flow-nexus.Service;
  homeStart = service.ExecStart;
  contextDeploy = pkgs.callPackage ../../packages/context-deploy { };
in
# The service resolves its tools through the declared profiles only.
assert !(builtins.any (entry: pkgs.lib.hasInfix ".local/bin" entry) service.Environment);
assert service.ExecStartPre == "${deployment.initialize}/bin/initialize-declared-flow";
assert inputs.flow.sourceInfo.rev == "2d2e2013f6fab3437e3088c4e52cc61fd2ed721a";
assert !(inputs ? flow-next);
assert
  module.config.content.systemd.user.services.flow-nexus.Service.ExecStartPost
  == "${deployment.ready}/bin/wait-declared-flow-ready";
assert
  homeStart
  == "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-03521/flow.memory None }\"";
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
    # One family declaration is atomic; accept only the two typed successes.
    # Zero-exit refusals and empty/transport replies must fail.
    cat > fake-flow-meta <<'SH'
    #!${pkgs.bash}/bin/bash
    printf '%s\n' "$1" >> "$CALL_LOG"
    case "$REPLY_MODE" in
      replaced) printf '%s\n' Configured.Replaced ;;
      unchanged) printf '%s\n' Configured.Unchanged ;;
      refused) printf '%s\n' ConfigureRejected.DuplicateEntry ;;
      transport) exit 7 ;;
      empty) : ;;
    esac
    SH
    chmod +x fake-flow-meta
    printf '%s\n' 'Configure.LeaveOuts.[ ]' > default-queries
    export CALL_LOG="$PWD/default-calls"
    for mode in replaced unchanged refused transport empty; do
      export REPLY_MODE="$mode"
      : > "$CALL_LOG"
      status=0
      ${pkgs.bash}/bin/bash ${../../packages/flow-deployment/apply-leave-outs.sh} "$PWD/fake-flow-meta" default-queries >default-reply 2>default-error || status=$?
      if test "$mode" = replaced || test "$mode" = unchanged; then
        test "$status" -eq 0
        test "$(wc -l < "$CALL_LOG")" -eq 1
      else
        test "$status" -ne 0
        test "$(wc -l < "$CALL_LOG")" -eq 1
      fi
    done
    for name in flow flow-meta flow-nexus flow-hook; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    test ! -e ${deployment}/share
    ${deployment}/bin/flow --version > cli-version
    ${deployment}/bin/flow-nexus --version > nexus-version
    test "$(cut -d ' ' -f 2 cli-version)" = "$(cut -d ' ' -f 2 nexus-version)"
    initializer=${deployment.initialize}/bin/initialize-declared-flow
    grep -F '[ gpt-5.6-sol gpt-5.6-luna ]' "$initializer"
    if grep -F 'gpt-5.6-terra' "$initializer"; then
      echo "retired Terra capability in Flow initializer" >&2
      exit 1
    fi
    # A foreign store and stale socket must report the child's refusal,
    # never send the single Configure request to a dead socket.
    export HOME="$TMPDIR/refused-home"
    export XDG_RUNTIME_DIR="$TMPDIR/refused-runtime"
    mkdir -p "$HOME/.local/state/flow-03521" "$XDG_RUNTIME_DIR/flow"
    printf 'foreign-store-preserve' > "$HOME/.local/state/flow-03521/flow.memory"
    cp "$HOME/.local/state/flow-03521/flow.memory" foreign-before
    python -c 'import os,socket; s=socket.socket(socket.AF_UNIX); s.bind(os.environ["XDG_RUNTIME_DIR"]+"/flow/flow-meta.sock"); s.close()'
    if "$initializer" > refused.log 2>&1; then
      echo "initializer accepted a foreign store" >&2
      exit 1
    fi
    grep -F 'Flow configuration child exited before socket readiness' refused.log
    ! grep -F 'Connection refused' refused.log
    cmp foreign-before "$HOME/.local/state/flow-03521/flow.memory"

    # A real configure-only child must become ready and consume exactly its
    # Configure request; no readiness connection is sent by the initializer.
    export HOME="$TMPDIR/accepted-home"
    export XDG_RUNTIME_DIR="$TMPDIR/accepted-runtime"
    mkdir -p "$HOME/.local/state/flow-production" "$XDG_RUNTIME_DIR"
    printf 'retained-original-cohort' > "$HOME/.local/state/flow-production/flow.memory"
    cp "$HOME/.local/state/flow-production/flow.memory" original-cohort-before
    "$initializer" > accepted.log 2>&1
    test "$(grep -Ec '^Configured\.(Replaced|Unchanged)$' accepted.log)" -eq 7
    "$initializer" > unchanged.log 2>&1
    test "$(grep -Fc Configured.Unchanged unchanged.log)" -eq 7
    cmp original-cohort-before "$HOME/.local/state/flow-production/flow.memory"
    # Startup ordering must wait for this actual daemon, not a stale pathname.
    ${runtime}/bin/flow-nexus "{ $XDG_RUNTIME_DIR/flow/flow.sock $XDG_RUNTIME_DIR/flow/flow-meta.sock $HOME/.local/state/flow-03521/flow.memory None }" >daemon.log 2>&1 &
    daemon_pid=$!
    trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" || true' EXIT
    MAINPID="$daemon_pid" ${deployment.ready}/bin/wait-declared-flow-ready
    FLOW_SOCKET="$XDG_RUNTIME_DIR/flow/flow.sock" ${runtime}/bin/flow Metaflows >metaflows.datom
    grep -F 'Listed.' metaflows.datom
    FLOW_META_SOCKET="$XDG_RUNTIME_DIR/flow/flow-meta.sock" ${runtime}/bin/flow-meta Configuration > configuration.datom
    python - <<'PYMODELS'
    import re
    from pathlib import Path
    text = Path("configuration.datom").read_text()
    rows = re.findall(r"\{ (Primary|Secondary|Tertiary|Quaternary) (Psyche|Mind|Field) ([^ }]+) \}", text)
    expected = {(layer, "Psyche"): model for layer, model in zip(
        ["Primary", "Secondary", "Tertiary", "Quaternary"],
        ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"])}
    expected.update({(layer, aspect): model for aspect in ["Mind", "Field"] for layer, model in zip(
        ["Primary", "Secondary", "Tertiary", "Quaternary"],
        ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-luna", "gpt-6-luna"])})
    assert len(rows) == 12, rows
    assert {(layer, aspect): model for layer, aspect, model in rows} == expected, rows
    PYMODELS
    grep -F '${
      inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default
    }/bin/message-mcp-send' configuration.datom
    # Original production bytes must never be opened or changed by this cohort.
    cmp original-cohort-before "$HOME/.local/state/flow-production/flow.memory"
    kill "$daemon_pid"
    wait "$daemon_pid"
    trap - EXIT
    # The activation's store check opens the store this Flow wrote, and
    # refuses one it cannot open, without changing either.
    cp "$HOME/.local/state/flow-03521/flow.memory" checked-before
    ${runtime}/bin/flow-store-check "{ $HOME/.local/state/flow-03521/flow.memory }" > store-check.datom
    grep -Fx "Opens.$HOME/.local/state/flow-03521/flow.memory" store-check.datom
    cmp checked-before "$HOME/.local/state/flow-03521/flow.memory"
    status=0
    ${runtime}/bin/flow-store-check "{ $TMPDIR/refused-home/.local/state/flow-03521/flow.memory }" > foreign-check.datom || status=$?
    test "$status" -ne 0
    grep -F 'Refused.' foreign-check.datom
    cmp foreign-before "$TMPDIR/refused-home/.local/state/flow-03521/flow.memory"
    python -c 'import os,signal,socket; root=os.environ["XDG_RUNTIME_DIR"]+"/flow/"; sockets=[socket.socket(socket.AF_UNIX) for _ in range(2)]; [(s.bind(root+n),s.listen()) for s,n in zip(sockets,["flow.sock","flow-meta.sock"])]; signal.pause()' >foreign-listener.log 2>&1 &
    foreign_pid=$!
    trap 'kill "$foreign_pid" 2>/dev/null || true; wait "$foreign_pid" || true' EXIT
    status=0
    MAINPID="$$" ${deployment.ready}/bin/wait-declared-flow-ready >foreign.log 2>&1 || status=$?
    test "$status" -ne 0
    grep -F 'did not own both listeners' foreign.log
    kill -0 "$foreign_pid"
    test -S "$XDG_RUNTIME_DIR/flow/flow.sock"
    test -S "$XDG_RUNTIME_DIR/flow/flow-meta.sock"
    kill "$foreign_pid"
    wait "$foreign_pid" || true
    trap - EXIT
    status=0
    MAINPID="$daemon_pid" ${deployment.ready}/bin/wait-declared-flow-ready >dead.log 2>&1 || status=$?
    test "$status" -ne 0
    grep -F 'Flow main process exited before readiness' dead.log
    mkdir -p "$out"
    cp cli-version nexus-version "$out/"
  ''
