{ pkgs, ... }:

pkgs.runCommand "solar-time-widget" { } ''
  set -eu

  widget=${../../modules/home/profiles/min/noctalia-plugins/solar-time/BarWidget.qml}
  manifest=${../../modules/home/profiles/min/noctalia-plugins/solar-time/manifest.json}
  sfwbar=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.jq}/bin/jq -e '.id == "solar-time" and .entryPoints.barWidget == "BarWidget.qml"' "$manifest"
  ${pkgs.gnugrep}/bin/grep -F '{ id = "plugin:solar-time"; }' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '/states/solar-time' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/solar-time/BarWidget.qml".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'Time.now' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'GetSolarClock' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'interval: 60000' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'waiting for a fresh authoritative GeoClue fix' "$widget"

  if ${pkgs.gnugrep}/bin/grep -E 'interval:[[:space:]]*(1000|[1-9][0-9]{0,2})([^0-9]|$)' "$widget" >/dev/null; then
    echo 'solar-time widget must not add a per-second display timer' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'latitude:|longitude:|coordinate[[:space:]]*=' "$widget" >/dev/null; then
    echo 'solar-time widget must not receive or display coordinates' >&2
    exit 1
  fi

  touch "$out"
''
