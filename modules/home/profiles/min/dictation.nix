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

  whisrsVocabularyTerms = [
    "Codex"
    "Claude"
    "CriomOS"
    "Niri"
    "Colemak"
    "OpenAI"
    "gopass"
    "whisrs"
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

    exec ${pkgs.systemd}/bin/systemctl --user restart whisrs.service
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
    whisrs
    listener
    listenerToggle
    listenerCancel
    pkgs.fuzzel
    pkgs.wl-clipboard
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
    status_bar = true
    vocabulary = ${builtins.toJSON whisrsVocabularyTerms}
    prompt = "Transcribe spoken English as dictated text. Preserve technical names from the vocabulary. Do not translate."

    [audio]
    device = "default"

    [input]
    key_delay_ms = 2

    [openai]
    api_key = ""
    model = "gpt-4o-transcribe"
  '';

  xdg.configFile."listener/environment.example".text = ''
    # Optional local overrides for Listener. Production transcription is owned
    # by listener-daemon and reads its OpenAI credential from gopass at runtime.
    # LISTENER_CAPTURE_PROGRAM=${pkgs.pulseaudio}/bin/parecord
    # LISTENER_CLIPBOARD_PROGRAM=${pkgs.wl-clipboard}/bin/wl-copy
  '';

  systemd.user.services.whisrs = {
    Unit = {
      Description = "whisrs dictation daemon";
      After = [
        "graphical-session.target"
        "pipewire.service"
        "pipewire-pulse.service"
      ];
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

  # When the network comes back after a transcription drop, retry every
  # spooled recording through whisrs's current backend. `--auto`
  # suppresses per-entry stdout chatter and only logs failures; the
  # daemon writes successful transcripts to history.jsonl + clipboard.
  # The unit is one-shot, depends on whisrs.service (so the daemon
  # exists to receive the IPC), and binds to network-online so
  # systemd fires it at the right moment.
  systemd.user.services.whisrs-spool-retry = {
    Unit = {
      Description = "Retry whisrs spooled recordings when the network returns";
      Requires = [ "whisrs.service" ];
      After = [
        "whisrs.service"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      # Sleep 2s before retrying so the daemon is fully up after a
      # cold boot ordering with network-online.target.
      ExecStart = "${pkgs.bash}/bin/bash -c 'sleep 2; ${whisrs}/bin/whisrs spool retry --all --auto || true'";
      RemainAfterExit = false;
    };
    Install.WantedBy = [ "network-online.target" ];
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
      action = a.spawn "${whisrs}/bin/whisrs" "toggle-copy";
      repeat = false;
      hotkey-overlay.title = "Voice Typing (Copy)";
    };

    binds."Mod+Alt+V" = {
      action = a.spawn "${whisrs}/bin/whisrs-recall";
      repeat = false;
      hotkey-overlay.title = "Voice Typing Recall";
    };

    binds."Mod+Ctrl+V" = {
      action = a.spawn "${whisrs}/bin/whisrs" "cancel";
      repeat = false;
      hotkey-overlay.title = "Voice Typing Cancel";
    };

    binds."Mod+M" = {
      action = a.spawn "${listenerToggle}/bin/listener-toggle-capture" "toggle";
      repeat = false;
      hotkey-overlay.title = "Listener Capture";
    };

    binds."Mod+Ctrl+M" = {
      action = a.spawn "${listenerCancel}/bin/listener-cancel-capture" "cancel";
      repeat = false;
      hotkey-overlay.title = "Listener Cancel";
    };

    binds."Mod+Alt+M" = {
      action = a.spawn "${listener}/bin/listener-recall";
      repeat = false;
      hotkey-overlay.title = "Listener Recall";
    };
  };
}
