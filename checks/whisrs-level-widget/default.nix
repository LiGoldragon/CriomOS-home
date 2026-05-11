{ pkgs, ... }:

pkgs.runCommand "whisrs-level-widget-reconnect" { } ''
  set -eu

  widget=${../../modules/home/profiles/min/noctalia-plugins/whisrs-level/BarWidget.qml}

  ${pkgs.gnugrep}/bin/grep -F 'function scheduleReconnect()' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'levelSocket.connected = false;' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'onError: _error => root.scheduleReconnect()' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'if (root.socketPath.length > 0)' "$widget"
  ! ${pkgs.gnugrep}/bin/grep -F 'if (!levelSocket.connected && root.socketPath.length > 0)' "$widget"

  touch "$out"
''
