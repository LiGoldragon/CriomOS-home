{ pkgs, ... }:

pkgs.runCommand "listener-level-widget" { } ''
  set -eu

  sfwbar=${../../modules/home/profiles/min/sfwbar.nix}

  ${pkgs.gnugrep}/bin/grep -F 'programs.noctalia = {' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'bar.main = {' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F '"control-center"' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'pre_action_fade_seconds = 5.0;' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'timeout = 300;' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'timeout = 3600;' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'Luau' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'leaves the Listener widget disabled until it is rewritten as a v5 plugin' "$sfwbar"
  ${pkgs.gnugrep}/bin/grep -F 'home.packages = [ pkgs.libnotify ];' "$sfwbar"

  if ${pkgs.gnugrep}/bin/grep -E '^[[:space:]]*programs\.noctalia-shell[[:space:]]*=' "$sfwbar" >/dev/null; then
    echo 'Noctalia v5 must use programs.noctalia, not programs.noctalia-shell' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -F 'plugin:listener-level' "$sfwbar" >/dev/null; then
    echo 'legacy QML listener-level plugin must not be wired into Noctalia v5' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -E 'file = .*plugins\.json|plugins/listener-level' "$sfwbar" >/dev/null; then
    echo 'legacy Noctalia plugin files must not be managed for Noctalia v5' >&2
    exit 1
  fi
  if ${pkgs.gnugrep}/bin/grep -F 'niri-title-only-updates.patch' "$sfwbar" >/dev/null; then
    echo 'legacy QML patch must not be applied to Noctalia v5 C++ source' >&2
    exit 1
  fi

  touch "$out"
''
