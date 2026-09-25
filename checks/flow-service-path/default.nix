{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  module = ../../modules/home/profiles/min/flow.nix;
  expectedFlowRevision = "2586ea19bf8ebd607490dec7b97a4e378c746407";
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
    config.criomosHome.flow.enable = false;
  };
  wrongUser = import module {
    inputs = moduleInputs;
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "another-user";
    config.criomos.corePackages = corePackages;
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
assert unit.content.Service.ExecStart == "${flowPackage}/bin/flow-nexus";
assert unit.content.Service.RuntimeDirectory == "flow";
assert builtins.elem "FLOW_SOURCE_ROOT=/home/li/primary" unit.content.Service.Environment;
assert builtins.elem "PATH=${expectedPath}" unit.content.Service.Environment;
assert unit.content.Unit.After == [ "codex-remote-control.service" ];
assert unit.content.Unit.Requires == [ "codex-remote-control.service" ];
assert !disabledUnit.condition;
assert !(builtins.elemAt wrongUser.config.assertions 0).assertion;
pkgs.runCommand "flow-service-path" { } ''
  mkdir -p "$out"
  printf '%s\n' '${expectedFlowRevision}' > "$out/flow-revision"
''
