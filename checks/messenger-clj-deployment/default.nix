{ inputs, pkgs, ... }:
let
  deployment = pkgs.callPackage ../../packages/messenger-clj-deployment { inherit inputs; };
  messenger = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  commands = [ "messenger-clj" "hm-send" "hm-send-abrupt" "hm-list" "hm-register" "hm-repair" "hm-deregister" "hm-rebind" "hm-move" "hm-retire" "hm-heartbeat-state" ];
  previous = pkgs.runCommand "previous-messenger-fixture" {} ''
    mkdir -p "$out/bin"
    printf '#!/bin/sh\nexit 0\n' > "$out/bin/messenger-clj"
    chmod +x "$out/bin/messenger-clj"
    ${pkgs.lib.concatMapStringsSep "\n" (name: "ln -s messenger-clj \"$out/bin/${name}\"") (builtins.tail commands)}
  '';
in pkgs.runCommand "messenger-clj-scoped-activation-check" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  home_dir="$TMPDIR/home"
  mkdir -p "$home_dir/.local/bin"
  ${pkgs.lib.concatMapStringsSep "\n" (name: "ln -s ${previous}/bin/${name} \"$home_dir/.local/bin/${name}\"") commands}
  printf 'unrelated' > "$home_dir/.local/bin/unrelated"
  rm "$home_dir/.local/bin/hm-retire"
  printf 'foreign' > "$home_dir/.local/bin/hm-retire"
  if ${deployment}/bin/activate-messenger-clj "$home_dir" ${previous}; then exit 1; fi
  ${pkgs.lib.concatMapStringsSep "\n" (name: "test \"$(readlink -f \"$home_dir/.local/bin/${name}\")\" = \"$(readlink -f ${previous}/bin/${name})\"") (builtins.filter (name: name != "hm-retire") commands)}
  test "$(cat "$home_dir/.local/bin/hm-retire")" = foreign
  rm "$home_dir/.local/bin/hm-retire"
  ln -s ${previous}/bin/hm-retire "$home_dir/.local/bin/hm-retire"
  ${deployment}/bin/activate-messenger-clj "$home_dir" ${previous}
  ${deployment}/bin/activate-messenger-clj "$home_dir" ${previous}
  ${pkgs.lib.concatMapStringsSep "\n" (name: "test \"$(readlink -f \"$home_dir/.local/bin/${name}\")\" = \"$(readlink -f ${messenger}/bin/${name})\"") commands}
  test "$(cat "$home_dir/.local/bin/unrelated")" = unrelated
  touch "$out"
''
