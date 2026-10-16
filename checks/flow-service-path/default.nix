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
assert inputs.flow.sourceInfo.rev == "da17d491aa1fa5b9a0e67bc9b1b16190eb7995cf";
assert !(inputs ? flow-next);
assert homeStart == "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-production/flow.sema }\"";
pkgs.runCommand "flow-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
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
    mkdir -p "$out"
    cp cli-version nexus-version "$out/"
  ''
