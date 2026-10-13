{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/flow-deployment { inherit inputs; };
  runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
assert inputs.flow.sourceInfo.rev == "9f159d03ae0bf5aa7f2a8d1c86ba7f386f69a057";
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
