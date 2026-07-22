{ pkgs, ... }:
let
  helper = ../../modules/home/profiles/min/noctalia-plugins/active-network/active_network_helper.py;
  widget = ../../modules/home/profiles/min/noctalia-plugins/active-network/BarWidget.qml;
  manifest = ../../modules/home/profiles/min/noctalia-plugins/active-network/manifest.json;
  module = ../../modules/home/profiles/min/active-network.nix;
  sfwbar = ../../modules/home/profiles/min/sfwbar.nix;
  helperTests = ./active_network_helper_test.py;
  fixtures = ./fixtures;
  helperPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.dbus-next ]);
in
pkgs.runCommand "active-network-widget" { } ''
  set -eu

  ${helperPython}/bin/python ${helperTests} ${helper} ${fixtures} ${widget}
  ${pkgs.jq}/bin/jq -e '.id == "active-network" and .entryPoints.barWidget == "BarWidget.qml"' ${manifest}

  ${pkgs.gnugrep}/bin/grep -F '{ id = "plugin:active-network"; }' ${sfwbar}
  ${pkgs.gnugrep}/bin/grep -F '/states/active-network' ${sfwbar}
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/active-network/BarWidget.qml".source' ${sfwbar}
  ${pkgs.gnugrep}/bin/grep -F './noctalia-plugins/active-network/active_network_helper.py' ${module}
  ${pkgs.gnugrep}/bin/grep -F 'NetworkManager event helper' ${module}
  ${pkgs.gnugrep}/bin/grep -F 'RuntimeDirectory = "active-network"' ${module}
  ${pkgs.gnugrep}/bin/grep -F 'Restart = "on-failure"' ${module}
  ${pkgs.gnugrep}/bin/grep -F 'RestartSec = "2s"' ${module}

  ${pkgs.gnugrep}/bin/grep -F 'function validateStatusEvent(event)' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'Number.isFinite(rssiValue)' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'Number.isInteger(event.bars)' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'const status = validateStatusEvent(JSON.parse(String(message)));' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'networkState = status.state;' ${widget}
  ${pkgs.gnugrep}/bin/grep -F '" dBm"' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'VPN' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'TooltipService.show(root, root.tooltipText)' ${widget}
  ${pkgs.gnugrep}/bin/grep -F 'root.signalBars' ${widget}

  ${pkgs.gnugrep}/bin/grep -F 'RSSI_REFRESH_SECONDS = 5' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'RSSI_STALE_SECONDS = 30' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'on_properties_changed' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'on_state_changed' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'asyncio.create_subprocess_exec' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'class SystemBusDisconnected' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'await self.bus.wait_for_disconnect()' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'CLIENT_DRAIN_TIMEOUT_SECONDS = 1' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'await asyncio.wait_for(' ${helper}
  ${pkgs.gnugrep}/bin/grep -F 'self.evict_client(writer, delivery)' ${helper}
  ${pkgs.gnugrep}/bin/grep -F '"dev",' ${helper}
  ${pkgs.gnugrep}/bin/grep -F '"link",' ${helper}
  if ${pkgs.gnugrep}/bin/grep -E 'RequestScan|nmcli|shell=True|subprocess\.run' ${helper}; then
    echo 'active-network helper must use NetworkManager signals and direct current-link iw only' >&2
    exit 1
  fi

  touch "$out"
''
