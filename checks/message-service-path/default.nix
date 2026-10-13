{ inputs, pkgs, ... }:
let
  deployment = pkgs.callPackage ../../packages/message-deployment { inherit inputs; };
  runtime = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
assert !(inputs ? message-next);
pkgs.runCommand "message-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    for name in message message-meta message-nexus; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    grep -Fx 'ExecStart=${runtime}/bin/message-nexus' ${deployment}/share/systemd/user/message-nexus.service
    grep -Fx 'Requires=flow-nexus.service' ${deployment}/share/systemd/user/message-nexus.service
    test "$(${deployment}/bin/message --version | awk '{print $NF}')" = "$(${deployment}/bin/message-nexus --version | awk '{print $NF}')"
    mkdir -p "$out"
  ''
