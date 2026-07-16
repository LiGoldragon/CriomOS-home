{ pkgs, ... }:

pkgs.runCommand "solar-time-widget" { } ''
  set -eu

  widget=${../../modules/home/profiles/min/noctalia-plugins/solar-time/BarWidget.qml}
  projection=${../../modules/home/profiles/min/noctalia-plugins/solar-time/SolarClock.js}
  projection_test=${./utc-projection-test.js}
  manifest=${../../modules/home/profiles/min/noctalia-plugins/solar-time/manifest.json}
  sfwbar=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.jq}/bin/jq -e '.id == "solar-time" and .entryPoints.barWidget == "BarWidget.qml"' "$manifest"
  ${pkgs.gnugrep}/bin/grep -F '{ id = "plugin:solar-time"; }' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '/states/solar-time' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/solar-time/BarWidget.qml".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'Time.now' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'GetSolarClock' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'interval: 60000' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'SolarClock.projectedText(sharedNow.getTime(), solarOffsetSeconds)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'apparentSolarDate.getUTCHours()' "$projection"
  ${pkgs.gnugrep}/bin/grep -F 'apparentSolarDate.getUTCMinutes()' "$projection"
  ${pkgs.gnugrep}/bin/grep -F 'apparentSolarDate.getUTCSeconds()' "$projection"
  ${pkgs.gnugrep}/bin/grep -F 'equation-of-time UTC-day validity boundary, not location freshness' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/solar-time/SolarClock.js".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'waiting for a fresh authoritative GeoClue fix' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'import qs.Services.UI' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'TooltipService.show(root, root.tooltipText)' "$widget"

  if ${pkgs.gnugrep}/bin/grep -E 'interval:[[:space:]]*(1000|[1-9][0-9]{0,2})([^0-9]|$)' "$widget" >/dev/null; then
    echo 'solar-time widget must not add a per-second display timer' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'Qt.formatTime|toISOString|getHours\(|getMinutes\(|getSeconds\(' "$widget" "$projection" >/dev/null; then
    echo 'solar-time widget must project apparent solar time in UTC rather than civil local time' >&2
    exit 1
  fi

  cat "$projection" "$projection_test" > utc-projection-test.js
  TZ=UTC ${pkgs.nodejs}/bin/node utc-projection-test.js
  TZ=Etc/GMT-2 ${pkgs.nodejs}/bin/node utc-projection-test.js
  TZ=America/Los_Angeles ${pkgs.nodejs}/bin/node utc-projection-test.js
  if ${pkgs.gnugrep}/bin/grep -F 'ToolTip.' "$widget" >/dev/null; then
    echo 'solar-time widget must use Noctalia TooltipService rather than an unstyled Qt tooltip' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'latitude:|longitude:|coordinate[[:space:]]*=' "$widget" >/dev/null; then
    echo 'solar-time widget must not receive or display coordinates' >&2
    exit 1
  fi

  touch "$out"
''
