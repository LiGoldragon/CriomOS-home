{
  pkgs,
  lib,
  config,
  user,
  constants,
  horizon,
  inputs,
  ...
}:
let
  terminal = "${pkgs.ghostty}/bin/ghostty";
  noctaliaShell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaExecutable = lib.getExe' noctaliaShell "noctalia";
  rescueTerminalPackage = pkgs.writeShellScriptBin "criomos-rescue-terminal" ''
    set -eu

    unit="criomos-rescue-terminal-$(${pkgs.coreutils}/bin/date +%s%N)-$$"
    exec ${pkgs.systemd}/bin/systemd-run --user --scope --collect --quiet \
      --unit="$unit" \
      --property=CPUWeight=1000 \
      --property=IOWeight=1000 \
      --property=MemoryAccounting=yes \
      --property=MemoryLow=256M \
      --property=MemoryHigh=2G \
      ${terminal} \
        --gtk-single-instance=false \
        --class=criomos-rescue-terminal \
        --title='CriomOS Rescue Terminal'
  '';
  rescueTerminal = "${rescueTerminalPackage}/bin/criomos-rescue-terminal";
  inherit (user) useFastRepeat;
  inherit (horizon.node) behavesAs;

  a = config.lib.niri.actions;
  screenshotDirectory = constants.fileSystem.home.screenshotDirectory;

  saveScreenshot = pkgs.writeShellScript "criomos-save-screenshot" ''
    set -eu

    screenshot_name="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).png"
    screenshot_path="$HOME/${screenshotDirectory}/$screenshot_name"

    if ${config.programs.niri.package}/bin/niri msg action screenshot-screen --path "$screenshot_path"; then
      wait_attempts=0
      while [ "$wait_attempts" -lt 20 ] && [ ! -s "$screenshot_path" ]; do
        wait_attempts=$((wait_attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.05
      done

      if [ ! -s "$screenshot_path" ]; then
        ${pkgs.libnotify}/bin/notify-send \
          --app-name="Screenshot" \
          --urgency=critical \
          --expire-time=8000 \
          --transient \
          "Screenshot failed" \
          "No screenshot file was written."
        exit 1
      fi
    else
      status="$?"
      ${pkgs.libnotify}/bin/notify-send \
        --app-name="Screenshot" \
        --urgency=critical \
        --expire-time=8000 \
        --transient \
        "Screenshot failed" \
        "Niri could not capture the screen."
      exit "$status"
    fi
  '';

  noctaliaIpc = pkgs.writeShellScript "criomos-noctalia-ipc" ''
    set -eu

    # Noctalia owns stable native message commands. Call the selected package
    # directly so profile rebuilds do not depend on a prior process image or
    # a QML-path-derived IPC endpoint.
    exec ${noctaliaExecutable} msg "$@"
  '';

  lockSession = pkgs.writeShellScript "criomos-lock-session" ''
    set -eu

    ${noctaliaIpc} session lock

    ${pkgs.coreutils}/bin/sleep 3
    ${config.programs.niri.package}/bin/niri msg action power-off-monitors || true
  '';

  lockListener = pkgs.writeShellScript "criomos-lock-listener" ''
    set -eu

    session_path=
    while [ -z "$session_path" ]; do
      session_id="''${XDG_SESSION_ID:-}"
      if [ -z "$session_id" ]; then
        session_id="$(${pkgs.systemd}/bin/loginctl show-user "$USER" -p Display --value 2>/dev/null || true)"
      fi

      if [ -n "$session_id" ]; then
        session_path="$(${pkgs.systemd}/bin/loginctl show-session "$session_id" -p Path --value 2>/dev/null || true)"
      fi

      if [ -z "$session_path" ]; then
        ${pkgs.coreutils}/bin/sleep 2
      fi
    done

    ${pkgs.glib}/bin/gdbus monitor --system --dest org.freedesktop.login1 --object-path "$session_path" \
      | while IFS= read -r line; do
          case "$line" in
            *".Lock"*)
              ${pkgs.systemd}/bin/systemctl --user start criomos-lock-session.service || true
              ;;
          esac
        done
  '';

  syncSessionEnvironment = pkgs.writeShellScript "criomos-sync-session-environment" ''
    set -eu

    ${pkgs.systemd}/bin/systemctl --user import-environment \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
  '';

in
{
  programs.niri.settings.environment = {
    "XDG_CURRENT_DESKTOP" = "niri:GNOME";
    "NOCTALIA_PAM_SERVICE" = "noctalia";
  };

  home.packages = [
    rescueTerminalPackage
  ]
  ++ (with pkgs; [
    grim
    slurp
    wl-clipboard
    gnome-control-center
  ]);

  systemd.user.services = lib.mkIf behavesAs.edge {
    criomos-lock-session = {
      Unit = {
        Description = "Lock the niri session";
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lockSession}";
      };
    };

    criomos-lock-listener = {
      Unit = {
        Description = "Forward logind lock requests to Noctalia";
        After = [ "default.target" ];
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStart = "${lockListener}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
  };

  # GNOME Settings' Bluetooth panel talks to this narrow settings-daemon
  # component on the user bus. Niri does not start a GNOME session, so make
  # that otherwise packaged component part of the desktop user environment.
  systemd.user.targets."org.gnome.SettingsDaemon.Rfkill" = lib.mkIf behavesAs.edge {
    Unit = {
      Description = "GNOME Settings Bluetooth rfkill integration";
      Wants = [ "org.gnome.SettingsDaemon.Rfkill.service" ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  programs.niri = {
    settings = {
      prefer-no-csd = true;
      xwayland-satellite.path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";

      input = {
        keyboard = {
          xkb = {
            layout = "us";
            options = "ctrl:nocaps,altwin:swap_ralt_rwin";
          };
          repeat-delay = if useFastRepeat then 200 else 600;
          repeat-rate = if useFastRepeat then 50 else 25;
        };
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = false;
        };
        mouse = {
          accel-profile = "flat";
        };
        focus-follows-mouse = {
          enable = true;
          max-scroll-amount = "0%";
        };
      };

      outputs."*" = {
        scale = 1.0;
      };

      workspaces.criomos-agent-tests = { };

      layout = {
        gaps = 8;
        default-column-width.proportion = 1.0;
        preset-column-widths = [
          { proportion = 0.33333; }
          { proportion = 0.5; }
          { proportion = 0.66667; }
          { proportion = 1.0; }
        ];
        center-focused-column = "never";

        border = {
          enable = false;
        };
        focus-ring = {
          enable = true;
          width = 3;
          active.color = "${config.lib.stylix.colors.withHashtag.base0D}";
          inactive.color = "${config.lib.stylix.colors.withHashtag.base02}";
        };
      };

      window-rules = [
        {
          geometry-corner-radius =
            let
              r = 8.0;
            in
            {
              top-left = r;
              top-right = r;
              bottom-left = r;
              bottom-right = r;
            };
          clip-to-geometry = true;
        }
        {
          matches = [
            { app-id = "^org\\.criome\\.AgentTestWindow$"; }
          ];
          open-on-workspace = "criomos-agent-tests";
          open-focused = false;
        }
        {
          matches = [
            { app-id = "^criomos-rescue-terminal$"; }
            { title = "^CriomOS Rescue Terminal$"; }
          ];
          open-focused = true;
        }
        {
          matches = [
            { app-id = "SolarFire|SolarFire\\.exe|solarfire"; }
            { title = "Solar Fire|SolarFire"; }
          ];
          open-floating = false;
        }
      ];

      spawn-at-startup = [
        { command = [ "${syncSessionEnvironment}" ]; }
        { command = [ "mako" ]; }
        { command = [ noctaliaExecutable ]; }
      ];

      animations = {
        window-open.kind.easing = {
          curve = "ease-out-expo";
          duration-ms = 200;
        };
        window-close.kind.easing = {
          curve = "ease-out-quad";
          duration-ms = 150;
        };
        workspace-switch.kind.easing = {
          curve = "ease-out-expo";
          duration-ms = 250;
        };
        horizontal-view-movement.kind.easing = {
          curve = "ease-out-expo";
          duration-ms = 200;
        };
        config-notification-open-close.kind.easing = {
          curve = "ease-out-quad";
          duration-ms = 200;
        };
      };

      binds = {
        # Launch
        "Mod+Shift+Return".action = a.spawn terminal "+new-window";
        "Mod+Ctrl+Return".action = a.spawn rescueTerminal;
        "Mod+O" = {
          action = a.toggle-overview;
          repeat = false;
        };
        # Noctalia's native CLI addresses its running instance directly.
        "Mod+D".action = a.spawn "${noctaliaIpc}" "panel-toggle" "launcher";
        "Mod+Space".action = a.spawn "${noctaliaIpc}" "panel-toggle" "launcher";

        # Window
        "Mod+Q".action = a.close-window;
        "Mod+T".action = a.fullscreen-window;
        "Mod+Alt+Delete".action = a.quit { skip-confirmation = true; };

        # Focus (Colemak: N=left I=right U=up E=down)
        "Mod+N".action = a.focus-column-left;
        "Mod+I".action = a.focus-column-right;
        "Mod+U".action = a.focus-window-up;
        "Mod+E".action = a.focus-window-down;

        # Move window
        "Mod+Shift+N".action = a.move-column-left;
        "Mod+Shift+I".action = a.move-column-right;
        "Mod+Shift+U".action = a.move-window-up;
        "Mod+Shift+E".action = a.move-window-down;

        # Column management
        "Mod+Comma".action = a.consume-window-into-column;
        "Mod+Period".action = a.expel-window-from-column;

        # Resize
        "Mod+R".action = a.switch-preset-column-width;
        "Mod+Minus".action = a.set-column-width "-10%";
        "Mod+Equal".action = a.set-column-width "+10%";
        "Mod+Shift+Minus".action = a.set-window-height "-10%";
        "Mod+Shift+Equal".action = a.set-window-height "+10%";
        "Mod+F".action = a.maximize-column;
        "Mod+B".action = a.center-column;

        # Workspaces (Colemak U=up E=down)
        "Mod+Ctrl+U".action = a.focus-workspace-up;
        "Mod+Ctrl+E".action = a.focus-workspace-down;
        "Mod+Ctrl+Shift+U".action = a.move-column-to-workspace-up;
        "Mod+Ctrl+Shift+E".action = a.move-column-to-workspace-down;
        "Mod+Page_Up".action = a.focus-workspace-up;
        "Mod+Page_Down".action = a.focus-workspace-down;
        "Mod+Shift+Page_Up".action = a.move-column-to-workspace-up;
        "Mod+Shift+Page_Down".action = a.move-column-to-workspace-down;

        # Tab/focus cycling
        "Mod+Tab".action = a.focus-workspace-previous;

        # Monitor (Colemak N=left I=right)
        "Mod+Ctrl+N".action = a.focus-monitor-left;
        "Mod+Ctrl+I".action = a.focus-monitor-right;
        "Mod+Ctrl+Shift+N".action = a.move-column-to-monitor-left;
        "Mod+Ctrl+Shift+I".action = a.move-column-to-monitor-right;

        # Numbered workspaces
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+Ctrl+1".action.move-window-to-workspace = 1;
        "Mod+Ctrl+2".action.move-window-to-workspace = 2;
        "Mod+Ctrl+3".action.move-window-to-workspace = 3;
        "Mod+Ctrl+4".action.move-window-to-workspace = 4;
        "Mod+Ctrl+5".action.move-window-to-workspace = 5;

        # Mouse scroll workspaces
        "Mod+WheelScrollDown" = {
          action = a.focus-workspace-down;
          cooldown-ms = 150;
        };
        "Mod+WheelScrollUp" = {
          action = a.focus-workspace-up;
          cooldown-ms = 150;
        };

        # Screenshot
        "Print".action = a.spawn "${saveScreenshot}";
        "Mod+P".action = a.spawn "sh" "-c" "grim - | wl-copy";
        "Mod+Print".action = a.spawn "sh" "-c" ''grim -g "$(slurp)" - | wl-copy'';

        # Volume
        "XF86AudioMute".action = a.spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";
        "XF86AudioRaiseVolume".action = a.spawn "wpctl" "set-volume" "-l" "1" "@DEFAULT_AUDIO_SINK@" "5%+";
        "XF86AudioLowerVolume".action = a.spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";

        # Lock
        "Mod+L".action = a.spawn "systemctl" "--user" "start" "criomos-lock-session.service";

        # Hotkey overlay
        "Mod+Shift+S".action = a.show-hotkey-overlay;
      };

      gestures = {
        hot-corners.enable = true;
      };
    };
  };
}
