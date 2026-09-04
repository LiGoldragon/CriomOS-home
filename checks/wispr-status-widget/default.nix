{ pkgs, inputs, ... }:

let
  noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
in

pkgs.runCommand "wispr-status-widget" { nativeBuildInputs = [ noctalia ]; } ''
  set -eu

  plugin=${../../modules/home/profiles/min/noctalia-plugins/wispr-status}
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT
  cp "$plugin/WisprStatusState.luau" "$workdir/WisprStatusState.luau"
  cp "$plugin/WisprStatusService.luau" "$workdir/WisprStatusService.luau"
  cp "$plugin/BarWidget.luau" "$workdir/BarWidget.luau"
  cp ${./service_behavior_test.luau} "$workdir/service_behavior_test.luau"
  cp ${./widget_behavior_test.luau} "$workdir/widget_behavior_test.luau"

  cd "$workdir"
  noctalia plugins lint "$plugin"
  ${pkgs.lua5_4}/bin/lua service_behavior_test.luau
  ${pkgs.lua5_4}/bin/lua widget_behavior_test.luau

  touch "$out"
''
