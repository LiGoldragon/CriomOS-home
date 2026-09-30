{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  module = ../../modules/home/profiles/min/flow.nix;
  expectedFlowRevision = "9fcd625ac7a0d44be58b9d365a94064e91f09219";
  flowPackage = pkgs.writeShellScriptBin "flow-nexus" "exit 0";
  herdrPackage = pkgs.writeShellScriptBin "herdr" "exit 0";
  flowIdPackage = pkgs.writeShellScriptBin "flow-id" "exit 0";
  codexPackage = pkgs.writeShellScriptBin "codex" "exit 0";
  claudePackage = pkgs.writeShellScriptBin "claude" "exit 0";
  moduleInputs = {
    flow.packages.${system}.default = flowPackage;
    herdr.packages.${system}.herdr = herdrPackage;
    harness.packages.${system}.default = flowIdPackage;
  };
  corePackages = {
    codex = codexPackage;
    claude = claudePackage;
  };
  expectedPath = lib.makeBinPath [
    herdrPackage
    flowIdPackage
    codexPackage
    claudePackage
  ];
  enabledByDefault = import module {
    inputs = moduleInputs;
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "li";
    config.criomos.corePackages = corePackages;
    config.criomosHome.codexNextCandidate = { hash = "candidatehash"; clientPackage = codexPackage; };
    config.criomosHome.flow = {
      enable = true;
      package = flowPackage;
    };
  };
  disabled = import module {
    inputs = moduleInputs;
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "li";
    config.criomos.corePackages = corePackages;
    config.criomosHome.codexNextCandidate = { hash = "candidatehash"; clientPackage = codexPackage; };
    config.criomosHome.flow = {
      enable = false;
      package = null;
    };
  };
  wrongUser = import module {
    inputs = moduleInputs;
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "another-user";
    config.criomos.corePackages = corePackages;
    config.criomosHome.codexNextCandidate = { hash = "candidatehash"; clientPackage = codexPackage; };
    config.criomosHome.flow = {
      enable = true;
      package = flowPackage;
    };
  };
  unit = enabledByDefault.config.systemd.user.services.flow-nexus;
  disabledUnit = disabled.config.systemd.user.services.flow-nexus;
in
assert unit.condition;
assert inputs.flow.sourceInfo.rev == expectedFlowRevision;
assert enabledByDefault.options.criomosHome.flow.enable.default;
assert enabledByDefault.options.criomosHome.flow.package.default == flowPackage;
assert unit.content.Service.ExecStart == "/nix/store/j689l77bmlfmgc6ichksrqnnmdnma8ig-flow-0.14.0/bin/flow-nexus";
assert unit.content.Service.RuntimeDirectory == "flow";
assert builtins.elem "FLOW_SOURCE_ROOT=/home/li/primary" unit.content.Service.Environment;
assert builtins.elem "PATH=/nix/store/9x03bz0q0a978zrzcshrlmmb4fvcmdb6-herdr-0.8.2/bin:/nix/store/b4wzlwmzbfis6ys2b1svh531dplxxyd3-harness-0.3.4/bin:/nix/store/wdj0sc69r4n9is1idfb32vcx5739ijkh-codex-0.153.4/bin:/nix/store/qsq3lh2i05dz77dakipwy9f1fkssq1zw-claude-code-2.1.284/bin" unit.content.Service.Environment;
assert builtins.elem "FLOW_CODEX_STABLE_SOCKET=/home/li/.codex/app-server-control/app-server-control.sock" unit.content.Service.Environment;
assert builtins.elem "FLOW_CODEX_NEXT_SOCKET=/home/li/.codex-next/app-server-control/app-server-control.sock" unit.content.Service.Environment;
assert unit.content.Unit.After == [ "codex-remote-control.service" ];
assert unit.content.Unit.Requires == [ "codex-remote-control.service" ];
assert !disabledUnit.condition;
assert !(builtins.elemAt wrongUser.config.assertions 1).assertion;
pkgs.runCommand "flow-service-path" { } ''
  mkdir -p "$out"
  printf '%s\n' '${expectedFlowRevision}' > "$out/flow-revision"
''
