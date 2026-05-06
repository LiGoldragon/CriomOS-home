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

  whisrs = pkgs.callPackage ../../../../packages/whisrs { inherit inputs; };

  whisrsServe = pkgs.writeShellScript "whisrs-daemon" ''
    set -eu

    WHISRS_OPENAI_API_KEY="$(${pkgs.gopass}/bin/gopass show -o openai/api-key)"
    if [ -z "$WHISRS_OPENAI_API_KEY" ]; then
      echo "whisrs-daemon: gopass openai/api-key returned an empty key" >&2
      exit 1
    fi

    export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
    ${pkgs.coreutils}/bin/install -d -m 700 "$XDG_DATA_HOME/whisrs"
    if [ -e "$XDG_DATA_HOME/whisrs/history.jsonl" ]; then
      ${pkgs.coreutils}/bin/chmod 600 "$XDG_DATA_HOME/whisrs/history.jsonl"
    else
      ${pkgs.coreutils}/bin/install -m 600 /dev/null "$XDG_DATA_HOME/whisrs/history.jsonl"
    fi

    export WHISRS_OPENAI_API_KEY
    export RUST_LOG="whisrs=info,warn"

    exec ${whisrs}/bin/whisrsd
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
    whisrs
    pkgs.wl-clipboard
    pkgs.wtype
  ];

  xdg.configFile."whisrs/config.toml".text = ''
    [general]
    backend = "openai"
    language = "en"
    notify = true
    remove_filler_words = false
    audio_feedback = false
    tray = true
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
      { command = [ "${startWhisrs}" ]; }
    ];

    binds."Mod+V" = {
      action = a.spawn "${whisrs}/bin/whisrs" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing";
    };

    binds."Mod+Shift+V" = {
      action = a.spawn "${whisrs}/bin/whisrs" "toggle-copy";
      repeat = false;
      hotkey-overlay.title = "Voice Typing (Copy)";
    };
  };
}
