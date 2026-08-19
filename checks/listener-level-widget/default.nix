{ pkgs, ... }:

let
  renderedWidget = pkgs.replaceVars ../../modules/home/profiles/min/noctalia-plugins/listener-level/level.luau {
    SOCAT = "${pkgs.socat}/bin/socat";
  };
in

pkgs.runCommand "listener-level-widget" { } ''
  set -eu

  widget=${../../modules/home/profiles/min/noctalia-plugins/listener-level/level.luau}
  renderedWidget=${renderedWidget}
  manifest=${../../modules/home/profiles/min/noctalia-plugins/listener-level/plugin.toml}
  sfwbar=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.python3}/bin/python -c '
import pathlib
import tomllib

manifest = tomllib.loads(pathlib.Path("'"$manifest"'").read_text())
assert manifest["id"] == "criomos/listener-level"
assert manifest["plugin_api"] == 23
assert "dependencies" not in manifest
assert manifest["widget"] == [{"id": "level", "entry": "level.luau"}]
'

  ${pkgs.gnugrep}/bin/grep -F 'plugins.enabled = [ "criomos/listener-level" ];' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'widget.listener-level.type = "criomos/listener-level:level";' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'bar.main = {' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"listener-level"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"launcher"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"workspaces"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"control-center"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/listener-level/plugin.toml".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"noctalia/plugins/listener-level/level.luau".source' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'listenerLevelWidget = pkgs.replaceVars' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'SOCAT = "''${pkgs.socat}/bin/socat";' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'listenerLevelWidget;' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'home.packages = [ pkgs.libnotify ];' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"app-name=Listener"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'history = 0;' "$sfwbar"
  if ${pkgs.gnugrep}/bin/grep -F 'plugin:whisrs-level' "$sfwbar" >/dev/null; then
    echo 'Whisrs level widget must not remain in the bar' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'bar\.widgets|(^|[[:space:]])(left|right)[[:space:]]*=' "$sfwbar" >/dev/null; then
    echo 'listener-level must use only Noctalia v5 bar.main start/center/end lanes' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'plugin:(solar-time|active-network)' "$sfwbar" >/dev/null; then
    echo 'unregistered v4 plugin entries must not remain in the v5 bar lanes' >&2
    exit 1
  fi

  ${pkgs.gnugrep}/bin/grep -F '/listener/status.sock' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '@SOCAT@ -u UNIX-CONNECT:' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '${pkgs.socat}/bin/socat -u UNIX-CONNECT:' "$renderedWidget"
  if ${pkgs.gnugrep}/bin/grep -F '@SOCAT@' "$renderedWidget" >/dev/null; then
    echo 'listener-level widget must render an absolute socat executable' >&2
    exit 1
  fi
  ${pkgs.gnugrep}/bin/grep -F 'noctalia.runStream' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'noctalia.json.decode(message)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "starting"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "recording"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "finalizing"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "transcribing"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "cancelling"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'next_state == "delivered"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'success_until_ms = now_ms + 700' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "cancelled"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'listener_state == "error"' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'tonumber(event.level)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'tonumber(event.in_flight)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'in_flight_count > 0' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'tostring(in_flight_count)' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'microphone_level * 2.75' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'visible_microphone_level' "$widget"
  ${pkgs.gnugrep}/bin/grep -F 'level_age_ms > 450' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#ef4444' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#f59e0b' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#facc15' "$widget"
  ${pkgs.gnugrep}/bin/grep -F '#38bdf8' "$widget"
  if ${pkgs.gnugrep}/bin/grep -F 'noctalia.notify' "$widget" >/dev/null; then
    echo 'listener-level widget must not duplicate Listener notifications' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'event\.(text|transcript)|transcript(Text|_text)' "$widget" >/dev/null; then
    echo 'listener-level widget must not carry transcript text' >&2
    exit 1
  fi

  touch "$out"
''
