{ pkgs, ... }:

pkgs.runCommand "listener-level-widget" { } ''
  set -eu

  widget=${../../modules/home/profiles/min/noctalia-plugins/listener-level/BarWidget.qml}
  manifest=${../../modules/home/profiles/min/noctalia-plugins/listener-level/manifest.json}
  sfwbar=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.jq}/bin/jq -e '.id == "listener-level" and .entryPoints.barWidget == "BarWidget.qml"' "$manifest"

  ${pkgs.gnugrep}/bin/grep -F '{ id = "plugin:listener-level"; }' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '/states/listener-level' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/listener-level/BarWidget.qml".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'home.packages = [ pkgs.libnotify ];' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"app-name=Listener"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'history = 0;' "$sfwbar"
  if ${pkgs.gnugrep}/bin/grep -F 'plugin:whisrs-level' "$sfwbar" >/dev/null; then
    echo 'Whisrs level widget must not remain in the bar' >&2
    exit 1
  fi

  ${pkgs.gnugrep}/bin/grep -F 'runtimeDirectory + "/listener/status.sock"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'JSON.parse(String(message))' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "starting"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "recording"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "finalizing"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "transcribing"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "cancelling"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'nextState === "delivered"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'successFlashTimer.restart()' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'interval: 700' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "cancelled"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listenerState === "error"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'Number(event.level || 0.0)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'microphoneLevel * 2.75' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'visibleMicrophoneLevel' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'levelAgeMilliseconds > 450' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#ef4444' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#f59e0b' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#facc15' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#38bdf8' "$widget"
  if ${pkgs.gnugrep}/bin/grep -F 'notify-send' "$widget" >/dev/null; then
    echo 'listener-level widget must not duplicate Listener notifications' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -F 'Process {' "$widget" >/dev/null; then
    echo 'listener-level widget must not create notification processes' >&2
    exit 1
  fi

  if ${pkgs.gnugrep}/bin/grep -E 'transcript|text' "$widget" >/dev/null; then
    echo 'listener-level widget must not carry transcript text' >&2
    exit 1
  fi

  touch "$out"
''
