{
  config,
  horizon,
  inputs,
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
  whisrs = pkgs.callPackage ../../../../packages/whisrs { inherit inputs; };

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

  whisrsServe = pkgs.writeShellScript "whisrs-daemon" ''
    set -eu

    WHISRS_OPENAI_API_KEY="$(${pkgs.gopass}/bin/gopass show -o openai/api-key)"
    if [ -z "$WHISRS_OPENAI_API_KEY" ]; then
      echo "whisrs-daemon: gopass openai/api-key returned an empty key" >&2
      exit 1
    fi

    uid="$(${pkgs.coreutils}/bin/id -u)"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
    export XDG_DATA_HOME="$runtime_dir/whisrs-data"
    ${pkgs.coreutils}/bin/mkdir -p "$XDG_DATA_HOME"

    export WHISRS_OPENAI_API_KEY
    export RUST_LOG="whisrs=info,warn"

    exec ${whisrs}/bin/whisrsd
  '';

  startHyprvoice = pkgs.writeShellScript "criomos-start-hyprvoice" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR

    exec ${pkgs.systemd}/bin/systemctl --user restart hyprvoice.service
  '';

  startWhisrs = pkgs.writeShellScript "criomos-start-whisrs" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT

    exec ${pkgs.systemd}/bin/systemctl --user restart whisrs.service
  '';
in
mkIf (size.atLeastMin && behavesAs.edge) {
  home.packages = [
    hyprvoice
    whisrs
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
    language = "en"
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

  xdg.configFile."whisrs/config.toml".text = ''
    [general]
    backend = "openai"
    language = "en"
    notify = true
    remove_filler_words = false
    audio_feedback = false
    tray = false
    overlay = false
    vocabulary = ["Codex", "Claude", "CriomOS", "Niri", "Colemak", "OpenAI", "gopass", "whisrs", "Hyprvoice"]
    prompt = "Transcribe spoken English as dictated text. Preserve technical names from the vocabulary. Do not translate."

    [audio]
    device = "default"

    [input]
    key_delay_ms = 2

    [openai]
    api_key = ""
    model = "gpt-4o-transcribe"
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

  systemd.user.services.whisrs = {
    Unit = {
      Description = "whisrs dictation daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Install.WantedBy = [ "graphical-session.target" ];

    Service = {
      ExecStart = "${whisrsServe}";
      Restart = "on-failure";
      RestartSec = 2;
      PassEnvironment = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_CURRENT_DESKTOP"
        "XDG_SESSION_TYPE"
        "XDG_RUNTIME_DIR"
        "HYPRLAND_INSTANCE_SIGNATURE"
        "NIRI_SOCKET"
        "SWAYSOCK"
        "XKB_DEFAULT_LAYOUT"
        "XKB_DEFAULT_VARIANT"
      ];
    };
  };

  programs.niri.settings = {
    spawn-at-startup = [
      { command = [ "${startHyprvoice}" ]; }
      { command = [ "${startWhisrs}" ]; }
    ];

    binds."Mod+V" = {
      action = a.spawn "${whisrs}/bin/whisrs" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing";
    };

    binds."Mod+Shift+V" = {
      action = a.spawn "${hyprvoice}/bin/hyprvoice" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing (Hyprvoice)";
    };
  };
}
