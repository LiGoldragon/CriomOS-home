{ pkgs, ... }:

pkgs.runCommand "wispr-status-widget" { } ''
  set -eu

  plugin=${../../modules/home/profiles/min/noctalia-plugins/wispr-status}
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT
  cp "$plugin/WisprStatusState.luau" "$workdir/WisprStatusState.luau"
  cp "$plugin/WisprStatusService.luau" "$workdir/WisprStatusService.luau"
  cp "$plugin/BarWidget.luau" "$workdir/BarWidget.luau"
  cp ${./state_behavior_test.luau} "$workdir/state_behavior_test.luau"
  cp ${./service_behavior_test.luau} "$workdir/service_behavior_test.luau"
  cp ${./widget_behavior_test.luau} "$workdir/widget_behavior_test.luau"

  cd "$workdir"
  ${pkgs.lua5_4}/bin/lua state_behavior_test.luau
  ${pkgs.lua5_4}/bin/lua service_behavior_test.luau
  ${pkgs.lua5_4}/bin/lua widget_behavior_test.luau

  touch "$out"
''
