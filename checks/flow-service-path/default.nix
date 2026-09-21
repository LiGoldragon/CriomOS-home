{ pkgs, ... }:
let
  inherit (pkgs) lib;
  module = ../../modules/home/profiles/min/flow.nix;
  flowPackage = pkgs.writeShellScriptBin "flow-nexus" "exit 0";
  enabled = import module {
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "li";
    config.criomosHome.flow = {
      enable = true;
      package = flowPackage;
    };
  };
  disabled = import module {
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "li";
    config.criomosHome.flow = {
      enable = false;
      package = null;
    };
  };
  wrongUser = import module {
    inherit lib pkgs;
    user.size = "Min";
    config.home.username = "another-user";
    config.criomosHome.flow = {
      enable = true;
      package = flowPackage;
    };
  };
  unit = enabled.config.systemd.user.services.flow-nexus;
  disabledUnit = disabled.config.systemd.user.services.flow-nexus;
in
assert unit.condition;
assert unit.content.Service.ExecStart == "${flowPackage}/bin/flow-nexus";
assert unit.content.Service.RuntimeDirectory == "flow";
assert unit.content.Unit.After == [ "codex-remote-control.service" ];
assert unit.content.Unit.Requires == [ "codex-remote-control.service" ];
assert !disabledUnit.condition;
assert !(builtins.elemAt wrongUser.config.assertions 1).assertion;
pkgs.runCommand "flow-service-path" { } ''
  touch "$out"
''
