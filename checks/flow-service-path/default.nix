{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  flowModule = ../../modules/home/profiles/min/flow.nix;
  flowPackage = inputs.flow.packages.${system}.default;
  homeDirectory = "/build/flow-service-home";

  moduleResult = import flowModule {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      home.username = "flow-test-user";
      criomosHome.flow.enable = true;
    };
  };
  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;
  service = moduleConfiguration.systemd.user.services.flow-nexus;
in
assert service.Unit.After == [ "codex-remote-control.service" ];
assert service.Unit.Requires == [ "codex-remote-control.service" ];
assert service.Service.ExecStart == "${flowPackage}/bin/flow-nexus";
assert service.Service.StateDirectory == "flow";
assert service.Service.RuntimeDirectory == "flow";
pkgs.runCommand "flow-service-path" { } ''
  test -x ${flowPackage}/bin/flow-nexus
  test -x ${flowPackage}/bin/flow
  test -x ${flowPackage}/bin/flow-meta
  touch "$out"
''
