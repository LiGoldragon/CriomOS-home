{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  module = ../../modules/home/profiles/min/flow.nix;
  expectedFlowRevision = "9aa9bf88e3ff6f3b68864eb300ee009897162ef4";
  flowPackage = pkgs.writeShellScriptBin "flow-nexus" "exit 0";
  messageNexusPath = "/nix/store/fixture-message/bin/message-nexus";
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
      inherit messageNexusPath;
    };
  };
  disabled = import module {
    inputs = moduleInputs;
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "li";
    config.criomos.corePackages = corePackages;
    config.criomosHome.flow = {
      enable = false;
      package = null;
      inherit messageNexusPath;
    };
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
      inherit messageNexusPath;
    };
  };
  unit = enabledByDefault.config.systemd.user.services.flow-nexus;
  disabledUnit = disabled.config.systemd.user.services.flow-nexus;
  configureUnit = enabledByDefault.config.systemd.user.services.flow-configuration;
  configureCommand = configureUnit.content.Service.ExecStart;
in
assert unit.condition;
assert inputs.flow.sourceInfo.rev == expectedFlowRevision;
assert enabledByDefault.options.criomosHome.flow.enable.default;
assert enabledByDefault.options.criomosHome.flow.package.default == flowPackage;
assert unit.content.Service.ExecStart == "${flowPackage}/bin/flow-nexus";
assert unit.content.Service.RuntimeDirectory == "flow";
assert builtins.elem "FLOW_SOURCE_ROOT=/home/li/primary" unit.content.Service.Environment;
assert builtins.elem "PATH=${expectedPath}" unit.content.Service.Environment;
assert builtins.elem "FLOW_CODEX_NEXT_SOCKET=/home/li/.codex-next/app-server-control/app-server-control.sock" unit.content.Service.Environment;
assert unit.content.Unit.After == [ "codex-remote-control.service" ];
assert unit.content.Unit.Requires == [ "codex-remote-control.service" ];
assert !disabledUnit.condition;
assert !(builtins.elemAt wrongUser.config.assertions 1).assertion;
# The privileged Configuration is declared, ordered behind the Nexus, and
# names the admitted Message Nexus executable in its last position.
assert configureUnit.condition;
assert configureUnit.content.Unit.After == [ "flow-nexus.service" ];
assert configureUnit.content.Unit.Requires == [ "flow-nexus.service" ];
assert configureUnit.content.Service.Type == "oneshot";
assert lib.hasInfix "Configure.{ %t/flow/flow.sock %t/flow/flow-meta.sock /home/li/primary " configureCommand;
assert lib.hasInfix "[ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ] [ Psyche ] ${messageNexusPath} }" configureCommand;
assert !disabled.config.systemd.user.services.flow-configuration.condition;
pkgs.runCommand "flow-service-path" { } ''
  mkdir -p "$out"
  printf '%s\n' '${expectedFlowRevision}' > "$out/flow-revision"
''
