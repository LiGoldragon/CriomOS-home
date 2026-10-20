# The declared Flow configuration is accepted whole by the Flow it deploys:
# the real initializer configures a fresh store through the real
# configure-only Nexus, and the snapshot read back holds the model
# thresholds, the Investigation seat and that seat's declaration. A query
# the Nexus refused would stop flow-nexus at its ExecStartPre; here it
# fails the check.
{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/flow-deployment { inherit inputs; };
  runtime = deployment.runtime;
in
pkgs.runCommand "flow-declared-configuration"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    export HOME="$PWD/home" XDG_RUNTIME_DIR="$PWD/run"
    mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
    ${deployment.initialize}/bin/initialize-declared-flow | tee initialized
    test "$(grep -c '^Configured\.' initialized)" -ge 7
    runtime_dir="$XDG_RUNTIME_DIR/flow"
    # The configure-only Nexus answers only Configure: a declaration the
    # store already holds whole answers Configured.Unchanged.
    holds() {
      local query="$1" reply child
      rm -f "$runtime_dir/flow-meta.sock"
      ${runtime}/bin/flow-nexus --configure-only "{ $runtime_dir/flow.sock $runtime_dir/flow-meta.sock $HOME/.local/state/${deployment.stateDirectory}/flow.sema None }" &
      child=$!
      for _attempt in $(seq 1 200); do
        test -S "$runtime_dir/flow-meta.sock" && break
        sleep 0.05
      done
      reply=$(FLOW_META_SOCKET="$runtime_dir/flow-meta.sock" ${runtime}/bin/flow-meta "$query")
      wait "$child"
      printf '%s -> %s\n' "''${query:0:60}" "$reply"
      test "$reply" = Configured.Unchanged
    }
    holds '${deployment.thresholds}'
    holds '${deployment.investigation}'
    holds "$(${pkgs.babashka}/bin/bb ${../../packages/flow-deployment/metaflows.clj} ${inputs.primary}/config/main-flow '${deployment.investigationSeat}')"
    # Each model a seat runs has its threshold; an OpenAI model's is lower.
    case '${deployment.thresholds}' in
      *"{ claude-opus-5-5 200000 }"*"{ gpt-6.1-sol 150000 }"*) ;;
      *) echo "thresholds not as declared" >&2; exit 1 ;;
    esac
    touch "$out"
  ''
