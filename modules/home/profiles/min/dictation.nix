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

  readActiveListenerSession = ''
    read_active_listener_session() {
      case "$1" in
        "(StatusReported (Capturing ("*)
          capture_prefix="(StatusReported (Capturing ("
          session_and_artifact="''${1#"$capture_prefix"}"
          session="''${session_and_artifact%% *}"
          case "$session" in
            "" | *[!0-9]*)
              return 1
              ;;
          esac
          printf '%s\n' "$session"
          ;;
        *)
          return 1
          ;;
      esac
    }
  '';

  listenerToggle = pkgs.writeShellScriptBin "listener-toggle-capture" ''
    set -eu

    ${readActiveListenerSession}

    status="$(${listener}/bin/listener status 2>/dev/null || true)"
    if [ -z "$status" ]; then
      ${pkgs.systemd}/bin/systemctl --user start listener.service
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        status="$(${listener}/bin/listener status 2>/dev/null || true)"
        [ -n "$status" ] && break
        sleep 0.2
      done
    fi

    case "$status" in
      "(StatusReported Idle)")
        exec ${listener}/bin/listener start
        ;;
      "(StatusReported (Capturing ("*)
        session="$(read_active_listener_session "$status")" || {
          echo "listener-toggle-capture: could not read active session from status: $status" >&2
          exit 1
        }
        exec ${listener}/bin/listener stop "$session"
        ;;
      *)
        echo "listener-toggle-capture: unexpected listener status: ''${status:-unavailable}" >&2
        exit 1
        ;;
    esac
  '';

  listenerCancel = pkgs.writeShellScriptBin "listener-cancel-capture" ''
    set -eu

    ${readActiveListenerSession}

    status="$(${listener}/bin/listener status 2>/dev/null || true)"
    session="$(read_active_listener_session "$status")" || {
      echo "listener-cancel-capture: no active Listener capture to cancel" >&2
      exit 0
    }

    exec ${listener}/bin/listener cancel "$session"
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
            # WirePlumber owns this address-derived loopback source and recreates
            # it when the Bluetooth profile changes. Keep this sidecar attached
            # only to that source; linger through a replacement instead of
            # falling back to whichever microphone happens to be default.
            target.object = "bluez_input.04:A8:5A:0B:EB:B0"
            node.dont-fallback = true
            node.linger = true
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

  xdg.configFile."wireplumber/wireplumber.conf.d/60-capture-policy.conf".text = ''
    # Default selection is priority-based, not a remembered transient node.
    # Audio/Source excludes sinks, monitors, and WirePlumber's internal
    # Bluetooth transport node; only real external capture endpoints qualify.
    wireplumber.settings = {
      bluetooth.autoswitch-to-headset-profile = false
      node.restore-default-targets = false
    }

    monitor.bluez.rules = [
      {
        # Keep the DJI in its capture-capable profile. The device name derives
        # from its Bluetooth address and survives node/profile recreation.
        matches = [
          {
            device.name = "bluez_card.04_A8_5A_0B_EB_B0"
          }
        ]
        actions = {
          update-props = {
            device.profile = "headset-head-unit"
            session.dont-restore-off-profile = true
            bluez5.auto-connect = [ hsp_ag hfp_ag ]
          }
        }
      }
      {
        matches = [
          {
            media.class = "Audio/Source"
            node.name = "~bluez_input.*"
          }
          {
            media.class = "Audio/Source"
            node.name = "~alsa_input.usb-.*"
          }
        ]
        actions = {
          update-props = {
            priority.session = 2200
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
