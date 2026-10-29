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
        stateDirectory = "flow-040";
        landingRepository = null;
        landingDeployRequest = null;
      };
    };
  };
  service = module.config.content.systemd.user.services.flow-nexus.Service;
  unit = module.config.content.systemd.user.services.flow-nexus.Unit;
  homeStart = service.ExecStart;
in
# The managed service opens only the complete typed configuration already in
# its preserved store. Configuration changes are revisioned FullConfigure
# transactions, never startup-time reconstructions from retired Primary EDN.
assert !(deployment ? initialize);
assert !(deployment ? leaveOutDefaults);
assert !(builtins.any (entry: pkgs.lib.hasInfix ".local/bin" entry) service.Environment);
assert
  !(builtins.any (entry: pkgs.lib.hasPrefix "FLOW_CORE_PRESENTATION_PROMPT=") service.Environment);
assert !(unit ? Requires);
assert builtins.elem "curriculum-nexus.service" unit.Wants;
assert builtins.elem "curriculum-nexus.service" unit.After;
assert service.ExecStartPre == "${deployment.storeCheck}/bin/check-declared-flow-store";
assert inputs.flow.sourceInfo.rev == "96ea3e7ebacd8f8210fb1cca2d5ad5af2f47acd4";
assert !(inputs ? flow-next);
assert service.ExecStartPost == "${deployment.ready}/bin/wait-declared-flow-ready";
assert
  homeStart
  == "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-040/flow.sema None }\"";
pkgs.runCommand "flow-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    for name in flow flow-meta flow-nexus flow-hook flow-harness-defaults; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    ${deployment.renderHarnesses}/bin/render-declared-flow-harnesses > harnesses.datom
    grep -F 'Configure.Harnesses.[' harnesses.datom
    for harness in claude codexStable codexNext; do
      grep -F "{ $harness " harnesses.datom
    done
    grep -F '${runtime}/bin/flow-store-check' ${deployment.storeCheck}/bin/check-declared-flow-store
    grep -F '/.local/state/flow-040/flow.sema' ${deployment.storeCheck}/bin/check-declared-flow-store
    if grep -R -E 'metaflows[.]clj|leave-outs[.]clj|Configure[.](Models|Thresholds|Investigation|Metaflows|LeaveOuts)' ${../../packages/flow-deployment}; then
      echo 'retired static Flow configuration remains in the declared deployment' >&2
      exit 1
    fi
    ${deployment}/bin/flow --version > cli-version
    ${deployment}/bin/flow-nexus --version > nexus-version
    test "$(cut -d ' ' -f 2 cli-version)" = "$(cut -d ' ' -f 2 nexus-version)"
    mkdir -p "$out"
    cp cli-version nexus-version harnesses.datom "$out/"
  ''
