{ pkgs, inputs, ... }:
let
  stable = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
  next = inputs.flow-next.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
        stablePackage = stable;
        nextPackage = next;
      };
    };
  };
  services = module.config.content.systemd.user.services;
  stableService = services.flow-nexus-04012;
  nextService = services.flow-nexus-next-0420;
  curriculumModule = import ../../modules/home/profiles/min/curriculum.nix {
    inherit inputs pkgs;
    lib = pkgs.lib;
    config = {
      home.homeDirectory = "/home/li";
      criomosHome.curriculum.enable = true;
    };
  };
  curriculumService = curriculumModule.config.content.systemd.user.services.curriculum-nexus-040;
  curriculumDeployment = pkgs.callPackage ../../packages/curriculum-resolver-deployment {
    inherit inputs;
  };
in
assert inputs.flow.sourceInfo.rev == "f3c59c4b15bb208ec4455f208d7ba0b103c65cd5";
assert inputs.flow-next.sourceInfo.rev == "806511305246f968d9164b4fd77bed46a7eef1ab";
assert stableService.Unit.Requires == [ "curriculum-nexus-040.service" ];
assert
  stableService.Service.ExecStart
  == ''${stable}/bin/flow-nexus "{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-040/flow.sema None }"'';
assert nextService.Unit.Requires == [ ];
assert
  nextService.Service.ExecStart
  == ''${next}/bin/flow-nexus "{ %t/flow-042-next/flow.sock %t/flow-042-next/flow-meta.sock %h/.local/state/flow-042-next/flow.sema None }"'';
assert stableService.Service.TimeoutStopSec == 90;
assert nextService.Service.TimeoutStopSec == 90;
assert
  curriculumService.Service.ExecStart == "${curriculumDeployment.runtime}/bin/curriculum-nexus";
assert builtins.elem "XDG_RUNTIME_DIR=%t/flow40-rt" curriculumService.Service.Environment;
assert
  curriculumModule.config.content.home.file.".local/state/curriculum-040/roles.datom".source
  == "${inputs.curriculum-source}/roles.datom";
pkgs.runCommand "flow-service-path" { } ''
  ${stable}/bin/flow-nexus --version > stable-version
  ${next}/bin/flow-nexus --version > next-version
  grep -Fx 'flow-nexus 0.40.12' stable-version
  grep -Fx 'flow-nexus 0.42.0' next-version
  mkdir -p "$out"
  cp stable-version next-version "$out/"
''
