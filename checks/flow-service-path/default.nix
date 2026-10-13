{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/flow-deployment { inherit inputs; };
  runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
assert inputs.flow.sourceInfo.rev == "d190e10aee27e4af45d5b8a5844c10e59e57b12b";
assert !(inputs ? flow-next);
pkgs.runCommand "flow-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    for name in flow flow-meta flow-nexus; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    grep -F 'ExecStart=${runtime}/bin/flow-nexus ' ${deployment}/share/systemd/user/flow-nexus.service
    ${deployment}/bin/flow --version > cli-version
    ${deployment}/bin/flow-nexus --version > nexus-version
    test "$(cut -d ' ' -f 2 cli-version)" = "$(cut -d ' ' -f 2 nexus-version)"
    mkdir -p "$out"
    cp cli-version nexus-version "$out/"
  ''
