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

  startDictationServices = pkgs.writeShellScript "criomos-start-dictation-services" ''
    set -eu

    # Quickshell scans plugins only at startup. After a Whisrs plugin
    # deploy, restart noctalia-shell if the widget renders but stops
    # updating; home-manager switch alone can leave the old plugin loaded.
    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR \
      HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET SWAYSOCK XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT

    ${pkgs.systemd}/bin/systemctl --user restart whisrs.service
    exec ${pkgs.systemd}/bin/systemctl --user restart dji-keepalive.service
  '';

  djiKeepalive = pkgs.writeShellScript "criomos-dji-keepalive" ''
    set -eu

    bluetooth_address="04:A8:5A:0B:EB:B0"
    bluetooth_identifier="04_A8_5A_0B_EB_B0"
    card_name="bluez_card.$bluetooth_identifier"
    device_path="/org/bluez/hci0/dev_04_A8_5A_0B_EB_B0"
    public_source_name="bluez_input.$bluetooth_address"
    keepalive_sink_name="dji_mic_keepalive"
    headset_profile="headset-head-unit"

    device_property() {
      ${pkgs.systemd}/bin/busctl get-property org.bluez "$device_path" org.bluez.Device1 "$1" 2>/dev/null
    }

    property_is_true() {
      test "$(device_property "$1" || true)" = "b true"
    }

    bluez_call() {
      ${pkgs.coreutils}/bin/timeout 8 ${pkgs.systemd}/bin/busctl call org.bluez "$device_path" org.bluez.Device1 "$@"
    }

    active_profile() {
      ${pkgs.pulseaudio}/bin/pactl list cards \
        | ${pkgs.gawk}/bin/awk -v card="$card_name" '
            $1 == "Name:" && $2 == card { in_card = 1; next }
            in_card && $1 == "Name:" { in_card = 0 }
            in_card && $1 == "Active" && $2 == "Profile:" { print $3; exit }
          '
    }

    pactl_name_exists() {
      list_kind="$1"
      expected_name="$2"
      ${pkgs.pulseaudio}/bin/pactl list short "$list_kind" \
        | ${pkgs.gawk}/bin/awk -v name="$expected_name" '$2 == name { found = 1 } END { exit found ? 0 : 1 }'
    }

    wait_for_bluez_connected() {
      for _ in $(${pkgs.coreutils}/bin/seq 1 12); do
        if property_is_true Connected; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "dji-keepalive: timed out waiting for BlueZ Connected" >&2
      return 1
    }

    wait_for_pactl_name() {
      list_kind="$1"
      expected_name="$2"
      for _ in $(${pkgs.coreutils}/bin/seq 1 12); do
        if pactl_name_exists "$list_kind" "$expected_name"; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "dji-keepalive: timed out waiting for $list_kind $expected_name" >&2
      return 1
    }

    ensure_keepalive_sink() {
      if pactl_name_exists sinks "$keepalive_sink_name"; then
        module_identifier=""
      else
        module_identifier="$(
          ${pkgs.pulseaudio}/bin/pactl load-module module-null-sink \
            "sink_name=$keepalive_sink_name" \
            "sink_properties=device.description=DJI-Mic-Keepalive"
        )"
      fi
      export module_identifier
      wait_for_pactl_name sinks "$keepalive_sink_name"
    }

    reassert_pipewire_profile() {
      if pactl_name_exists cards "$card_name"; then
        ${pkgs.pulseaudio}/bin/pactl set-card-profile "$card_name" "$headset_profile" || true
      fi
      if pactl_name_exists sources "$public_source_name"; then
        ${pkgs.pulseaudio}/bin/pactl set-default-source "$public_source_name" || true
      fi
    }

    unload_keepalive_sink() {
      if test -n "''${module_identifier:-}"; then
        ${pkgs.pulseaudio}/bin/pactl unload-module "$module_identifier" >/dev/null 2>&1 || true
      fi
    }

    prepare_profile() {
      if ! property_is_true Connected; then
        bluez_call Connect || true
      fi
      wait_for_bluez_connected
      wait_for_pactl_name cards "$card_name"

      reassert_pipewire_profile
      for _ in $(${pkgs.coreutils}/bin/seq 1 12); do
        if test "$(active_profile)" = "$headset_profile"; then
          wait_for_pactl_name sources "$public_source_name"
          ${pkgs.pulseaudio}/bin/pactl set-default-source "$public_source_name" || true
          return 0
        fi
        reassert_pipewire_profile
        ${pkgs.coreutils}/bin/sleep 1
      done

      echo "dji-keepalive: $card_name did not enter $headset_profile" >&2
      return 1
    }

    run_keepalive() {
      prepare_profile
      ensure_keepalive_sink

      ${pkgs.pipewire}/bin/pw-loopback \
        --capture "$public_source_name" \
        --playback "$keepalive_sink_name" \
        --capture-props='node.name="dji-mic-keepalive-capture" media.name="DJI Mic Keepalive Capture" application.name="DJI Mic Keepalive"' \
        --playback-props='node.name="dji-mic-keepalive-playback" media.name="DJI Mic Keepalive Sink Feed" application.name="DJI Mic Keepalive"' &
      child="$!"
      retry_delay_seconds=3
      stop_child() {
        kill "$child" 2>/dev/null || true
        unload_keepalive_sink
      }
      exit_after_signal() {
        stop_child
        exit 143
      }
      trap stop_child EXIT
      trap exit_after_signal INT TERM

      while kill -0 "$child" 2>/dev/null; do
        if ! property_is_true Connected; then
          echo "dji-keepalive: BlueZ device state dropped" >&2
          stop_child
          wait "$child" 2>/dev/null || true
          trap - EXIT INT TERM
          return 1
        fi
        if ! test "$(active_profile)" = "$headset_profile"; then
          echo "dji-keepalive: $card_name left $headset_profile; reasserting PipeWire profile without reconnecting Bluetooth" >&2
          reassert_pipewire_profile
        fi
        if ! pactl_name_exists sources "$public_source_name" || ! pactl_name_exists sinks "$keepalive_sink_name"; then
          echo "dji-keepalive: PipeWire source or keepalive sink disappeared" >&2
          stop_child
          wait "$child" 2>/dev/null || true
          trap - EXIT INT TERM
          return 1
        fi
        ${pkgs.coreutils}/bin/sleep 15
      done

      set +e
      wait "$child"
      result="$?"
      set -e
      unload_keepalive_sink
      trap - EXIT INT TERM
      return "$result"
    }

    retry_delay_seconds=3
    while true; do
      run_keepalive || true
      ${pkgs.coreutils}/bin/sleep "$retry_delay_seconds"
      if test "$retry_delay_seconds" -lt 30; then
        retry_delay_seconds=$((retry_delay_seconds + 3))
      fi
    done
  '';
in
mkIf (size.min && behavesAs.edge) {
  home.packages = [
    whisrs
    pkgs.fuzzel
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
    status_bar = true
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

  systemd.user.services.dji-keepalive = {
    Unit = {
      Description = "DJI Mic 2 Bluetooth capture keepalive";
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
      Wants = [
        "pipewire.service"
        "wireplumber.service"
      ];
      PartOf = [ "graphical-session.target" ];
    };

    Install.WantedBy = [ "graphical-session.target" ];

    Service = {
      ExecStart = "${djiKeepalive}";
      Restart = "always";
      RestartSec = 2;
    };
  };

  home.activation.restartDjiKeepalive = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if ${pkgs.systemd}/bin/systemctl --user --quiet is-active graphical-session.target; then
      run ${pkgs.systemd}/bin/systemctl --user daemon-reload
      run ${pkgs.systemd}/bin/systemctl --user restart dji-keepalive.service || true
    fi
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

    binds."Mod+Shift+V" = {
      action = a.spawn "${whisrs}/bin/whisrs" "toggle";
      repeat = false;
      hotkey-overlay.title = "Voice Typing";
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
  };
}
