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

  listener = inputs.listener.packages.${pkgs.stdenv.hostPlatform.system}.default;

  listenerTranscriptionVocabularyTerms = [
    "Mentci"
    "Criome"
    "SEMA"
    "pi"
    "P-I"
    "CriomOS"
    "NOTA"
    "Niri"
    "Noctalia"
    "QuickShell"
    "Whisrs"
    "gopass"
    "Colemak"
    "PipeWire"
    "WirePlumber"
    "Kameo"
    "Nexus"
    "Spirit"
    "Orchestrate"
    "Lojix"
    "rkyv"
  ];

  listenerTranscriptionVocabulary = pkgs.writeText "listener-transcription-vocabulary.txt" (
    lib.concatStringsSep "\n" listenerTranscriptionVocabularyTerms + "\n"
  );

  listenerTranscriptionCustomization = pkgs.runCommand "listener-transcription-customization" { } ''
    set -eu
    mkdir -p "$out"
    ${listener}/bin/listener-transcription-customization \
      ${listenerTranscriptionVocabulary} \
      "$out/transcription-customization.rkyv"
    test -s "$out/transcription-customization.rkyv"
    cp ${listenerTranscriptionVocabulary} "$out/terms.txt"
  '';

  startDictationServices = pkgs.writeShellScript "criomos-start-dictation-services" ''
    set -eu

    # Quickshell scans plugins only at startup. After a dictation
    # plugin deploy, restart noctalia-shell if a widget renders but
    # stops updating; home-manager switch alone can leave old plugin
    # code loaded.
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT

    exec ${pkgs.systemd}/bin/systemctl --user restart listener.service
  '';

  listenerServe = pkgs.writeShellScript "listener-daemon" ''
    set -eu

    export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
    export LISTENER_CAPTURE_PROGRAM="''${LISTENER_CAPTURE_PROGRAM:-${pkgs.pulseaudio}/bin/parecord}"
    export LISTENER_CLIPBOARD_PROGRAM="''${LISTENER_CLIPBOARD_PROGRAM:-${pkgs.wl-clipboard}/bin/wl-copy}"
    export LISTENER_TRANSCRIPTION_CUSTOMIZATION_ARCHIVE="${listenerTranscriptionCustomization}/transcription-customization.rkyv"
    exec ${listener}/bin/listener-daemon
  '';

  listenerToggle = pkgs.writeShellScriptBin "listener-toggle-capture" ''
    set -eu

    # Toggle is one daemon-owned transition. Do not read status and issue a
    # follow-up start/stop request: that race can target a different session.
    ${pkgs.systemd}/bin/systemctl --user start listener.service
    exec ${listener}/bin/listener toggle
  '';

  listenerCancel = pkgs.writeShellScriptBin "listener-cancel-capture" ''
    set -eu

    status="$(${listener}/bin/listener status 2>/dev/null || true)"
    case "$status" in
      "StatusReported.Capturing.{"*)
        session_and_artifact="''${status#StatusReported.Capturing.\{}"
        session="''${session_and_artifact%% *}"
        case "$session" in
          "" | *[!0-9]*)
            echo "listener-cancel-capture: could not read active session" >&2
            exit 1
            ;;
        esac
        exec ${listener}/bin/listener cancel "$session"
        ;;
      *)
        exit 0
        ;;
    esac
  '';
in
mkIf (size.min && behavesAs.edge) {
  home.packages = [
    listener
    listenerToggle
    listenerCancel
    pkgs.fuzzel
    pkgs.wl-clipboard
  ];

  xdg.configFile."listener/environment.example".text = ''
    # Optional local overrides for Listener. Production transcription is owned
    # by listener-daemon and reads its OpenAI credential from gopass at runtime.
    # LISTENER_CAPTURE_PROGRAM=${pkgs.pulseaudio}/bin/parecord
    # LISTENER_CLIPBOARD_PROGRAM=${pkgs.wl-clipboard}/bin/wl-copy
  '';

  systemd.user.services.listener = {
    Unit = {
      Description = "Listener speech-to-text daemon";
      After = [
        "graphical-session.target"
        "pipewire.service"
        "pipewire-pulse.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };

    Install.WantedBy = [ "graphical-session.target" ];

    Service = {
      ExecStart = "${listenerServe}";
      Restart = "on-failure";
      RestartSec = 2;
      UMask = "0077";
      EnvironmentFile = "-%h/.config/listener/environment";
      PassEnvironment = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_CURRENT_DESKTOP"
        "XDG_SESSION_TYPE"
        "XDG_RUNTIME_DIR"
      ];
    };
  };

  xdg.configFile."pipewire/pipewire.conf.d/60-dji-mic-keepalive.conf".text = ''
    context.objects = [
      {
        factory = adapter
        args = {
          factory.name = support.null-audio-sink
          media.class = "Audio/Sink"
          node.name = "dji_mic_keepalive_sink"
          node.description = "DJI Mic Keepalive Sink"
          object.linger = true
          monitor.channel-volumes = true
          priority.session = 1
          audio.position = [ MONO ]
        }
      }
    ]

    context.modules = [
      {
        name = libpipewire-module-loopback
        args = {
          node.description = "DJI Mic Keepalive"
          capture.props = {
            node.name = "dji_mic_keepalive_capture"
            target.object = "bluez_input.04:A8:5A:0B:EB:B0"
            audio.position = [ MONO ]
            stream.dont-remix = true
            node.passive = false
          }
          playback.props = {
            node.name = "dji_mic_keepalive_playback"
            target.object = "dji_mic_keepalive_sink"
            audio.position = [ MONO ]
            stream.dont-remix = true
            node.passive = false
          }
        }
      }
    ]
  '';

  xdg.configFile."wireplumber/wireplumber.conf.d/60-dji-source-priority.conf".text = ''
    monitor.bluez.rules = [
      {
        matches = [
          {
            node.name = "bluez_input.04_A8_5A_0B_EB_B0.0"
          }
        ]
        actions = {
          update-props = {
            priority.session = 3000
          }
        }
      }
    ]
  '';

  programs.niri.settings = {
    spawn-at-startup = [
      { command = [ "${startDictationServices}" ]; }
    ];

    binds."Mod+V" = {
      action = a.spawn "${listenerToggle}/bin/listener-toggle-capture" "toggle";
      repeat = false;
      hotkey-overlay.title = "Listener Capture";
    };

    binds."Mod+Alt+V" = {
      action = a.spawn "${listener}/bin/listener-recall";
      repeat = false;
      hotkey-overlay.title = "Listener Recall";
    };

    binds."Mod+Ctrl+V" = {
      action = a.spawn "${listenerCancel}/bin/listener-cancel-capture" "cancel";
      repeat = false;
      hotkey-overlay.title = "Listener Cancel";
    };
  };
}
