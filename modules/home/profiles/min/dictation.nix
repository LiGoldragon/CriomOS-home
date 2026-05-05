{
  config,
  horizon,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (horizon.node) behavesAs;
  inherit (user) size;

  a = config.lib.niri.actions;

  hyprvoice = pkgs.callPackage ../../../../packages/hyprvoice { };

  hyprvoiceServe = pkgs.writeShellScript "hyprvoice-serve" ''
    set -eu

    OPENAI_API_KEY="$(${pkgs.gopass}/bin/gopass show -o openai/api-key)"
    if [ -z "$OPENAI_API_KEY" ]; then
      echo "hyprvoice-serve: gopass openai/api-key returned an empty key" >&2
      exit 1
    fi

    export OPENAI_API_KEY
    export YDOTOOL_SOCKET="''${YDOTOOL_SOCKET:-/run/ydotoold/socket}"

    exec ${hyprvoice}/bin/hyprvoice serve
  '';

  startHyprvoice = pkgs.writeShellScript "criomos-start-hyprvoice" ''
    set -eu

    export YDOTOOL_SOCKET="''${YDOTOOL_SOCKET:-/run/ydotoold/socket}"

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR YDOTOOL_SOCKET
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR YDOTOOL_SOCKET

    exec ${pkgs.systemd}/bin/systemctl --user restart hyprvoice.service
  '';
in
mkIf (size.atLeastMin && behavesAs.edge) {
  home.packages = [ hyprvoice ];

  xdg.configFile."hyprvoice/config.toml".text = ''
    [recording]
    sample_rate = 16000
    channels = 1
    format = "s16"
    buffer_size = 8192
    device = ""
    channel_buffer_size = 30
    timeout = "5m"

    [transcription]
    provider = "openai"
    model = "gpt-4o-transcribe"
    language = ""
    streaming = false
    threads = 0

    [injection]
    backends = ["ydotool", "clipboard"]
    ydotool_timeout = "5s"
    wtype_timeout = "5s"
    clipboard_timeout = "3s"

    [notifications]
    enabled = true
    type = "desktop"

    [llm]
    enabled = false
  '';

  systemd.user.services.hyprvoice = {
    Unit = {
      Description = "Hyprvoice dictation daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${hyprvoiceServe}";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "YDOTOOL_SOCKET=/run/ydotoold/socket"
      ];
    };
  };

  programs.niri.settings = {
    spawn-at-startup = [
      { command = [ "${startHyprvoice}" ]; }
    ];

    binds."Mod+V" = {
      action = a.spawn "${hyprvoice}/bin/hyprvoice" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing";
    };
  };
}
