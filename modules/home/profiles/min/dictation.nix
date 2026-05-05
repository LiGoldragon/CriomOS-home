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
  voxtype = pkgs.callPackage ../../../../packages/voxtype { };

  hyprvoiceServe = pkgs.writeShellScript "hyprvoice-serve" ''
    set -eu

    OPENAI_API_KEY="$(${pkgs.gopass}/bin/gopass show -o openai/api-key)"
    if [ -z "$OPENAI_API_KEY" ]; then
      echo "hyprvoice-serve: gopass openai/api-key returned an empty key" >&2
      exit 1
    fi

    export OPENAI_API_KEY

    exec ${hyprvoice}/bin/hyprvoice serve
  '';

  voxtypeServe = pkgs.writeShellScript "voxtype-daemon" ''
    set -eu

    VOXTYPE_WHISPER_API_KEY="$(${pkgs.gopass}/bin/gopass show -o openai/api-key)"
    if [ -z "$VOXTYPE_WHISPER_API_KEY" ]; then
      echo "voxtype-daemon: gopass openai/api-key returned an empty key" >&2
      exit 1
    fi

    export VOXTYPE_WHISPER_API_KEY
    export PATH="${
      lib.makeBinPath [
        pkgs.libnotify
        pkgs.wl-clipboard
        pkgs.wtype
      ]
    }:$PATH"

    exec ${voxtype}/bin/voxtype daemon --no-hotkey
  '';

  startHyprvoice = pkgs.writeShellScript "criomos-start-hyprvoice" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR

    exec ${pkgs.systemd}/bin/systemctl --user restart hyprvoice.service
  '';

  startVoxtype = pkgs.writeShellScript "criomos-start-voxtype" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR

    exec ${pkgs.systemd}/bin/systemctl --user restart voxtype.service
  '';
in
mkIf (size.atLeastMin && behavesAs.edge) {
  home.packages = [
    hyprvoice
    voxtype
    pkgs.wl-clipboard
    pkgs.wtype
  ];

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
    # wtype uses Wayland virtual-keyboard text injection; clipboard remains
    # available as the explicit non-typing backend.
    backends = ["wtype", "clipboard"]
    ydotool_timeout = "5s"
    wtype_timeout = "60s"
    clipboard_timeout = "3s"

    [notifications]
    enabled = true
    type = "desktop"

    [llm]
    enabled = false
  '';

  xdg.configFile."voxtype/config.toml".text = ''
    engine = "whisper"
    state_file = "auto"

    [hotkey]
    enabled = false
    mode = "toggle"

    [audio]
    device = "default"
    sample_rate = 16000
    max_duration_secs = 300

    [audio.feedback]
    enabled = false

    [whisper]
    mode = "remote"
    remote_endpoint = "https://api.openai.com"
    remote_model = "gpt-4o-transcribe"
    language = "en"
    translate = false
    remote_timeout_secs = 120

    [output]
    mode = "paste"
    fallback_to_clipboard = false
    auto_submit = false
    append_text = " "
    shift_enter_newlines = false
    paste_keys = "ctrl+v"
    restore_clipboard = true
    restore_clipboard_delay_ms = 500

    [output.notification]
    on_recording_start = true
    on_recording_stop = true
    on_transcription = false

    [text]
    spoken_punctuation = false
    smart_auto_submit = false
  '';

  systemd.user.services.hyprvoice = {
    Unit = {
      Description = "Hyprvoice dictation daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install.WantedBy = [ "graphical-session.target" ];

    Service = {
      ExecStart = "${hyprvoiceServe}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.user.services.voxtype = {
    Unit = {
      Description = "Voxtype dictation daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install.WantedBy = [ "graphical-session.target" ];

    Service = {
      ExecStart = "${voxtypeServe}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  programs.niri.settings = {
    spawn-at-startup = [
      { command = [ "${startHyprvoice}" ]; }
      { command = [ "${startVoxtype}" ]; }
    ];

    binds."Mod+V" = {
      action = a.spawn "${hyprvoice}/bin/hyprvoice" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing";
    };

    binds."Mod+Shift+V" = {
      action =
        a.spawn "${voxtype}/bin/voxtype" "record" "toggle" "--paste" "--no-auto-submit"
          "--no-smart-auto-submit";
      repeat = false;
      hotkey-overlay.title = "Voice Typing (Voxtype)";
    };
  };
}
