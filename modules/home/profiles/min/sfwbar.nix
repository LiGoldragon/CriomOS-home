{
  lib,
  config,
  hexis,
  horizon,
  inputs,
  pkgs,
  ...
}:
let
  inherit (horizon.node) behavesAs;
  colors = config.lib.stylix.colors.withHashtag;
  noctaliaShell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  listenerLevelWidget = pkgs.replaceVars ./noctalia-plugins/listener-level/level.luau {
    SOCAT = "${pkgs.socat}/bin/socat";
  };
  listenerTranscriptPanel = pkgs.replaceVars ./noctalia-plugins/listener-level/transcript-panel.luau {
    SOCAT = "${pkgs.socat}/bin/socat";
  };
  wisprStatusService = pkgs.replaceVars ./noctalia-plugins/wispr-status/WisprStatusService.luau {
    SOCAT = "${pkgs.socat}/bin/socat";
  };
in
lib.mkIf behavesAs.edge {
  home.packages = [ pkgs.libnotify ];

  programs.noctalia = {
    enable = true;
    package = noctaliaShell;
    systemd.enable = false;
    settings = {
      theme = {
        # Chroma is the sole light/dark authority.  Noctalia consumes its
        # portal-published external mode, retaining its wallpaper palette
        # without writing a competing global color-scheme value.
        mode = lib.mkForce "external";
        source = lib.mkForce "wallpaper";
        wallpaper_scheme = lib.mkForce "m3-rainbow";
      };
      idle = {
        pre_action_fade_seconds = 5;
        behavior = {
          "screen-off" = {
            enabled = true;
            timeout = 300;
            action = "screen_off";
          };
          lock = {
            enabled = true;
            timeout = 3600;
            action = "lock";
          };
        };
      };
      plugins.enabled = [
        "criomos/wispr-status"
        "criomos/listener-level"
      ];
      widget.wispr-status-widget.type = "criomos/wispr-status:wispr-status-widget";
      widget.listener-level.type = "criomos/listener-level:level";
      widget.tray.drawer = true;
      widget.battery.display_mode = "graphic";
      bar.main = {
        margin_ends = 0;
        start = [
          "launcher"
          "clock"
          "media"
        ];
        center = [
          "workspaces"
        ];
        end = [
          "wispr-status-widget"
          "listener-level"
          "tray"
          "battery"
          "volume"
          "brightness"
          "control-center"
        ];
      };
    };
  };

  # Noctalia overlays this mutable state file after the declarative config and
  # uses its enabled-plugin list while constructing the startup registry.
  # Reconcile only those two authority boundaries; wallpaper, palette, and
  # other user state remain untouched.
  home.activation.reconcileNoctaliaSettings = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.local/state/noctalia/settings.toml";
    declared = {
      theme.mode = "external";
      plugins.enabled = [
        "criomos/wispr-status"
        "criomos/listener-level"
      ];
    };
    modes = {
      "/theme/mode" = "always";
      "/plugins/enabled" = "always";
    };
  };

  home.activation.mergeNoctaliaPlugins = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.config/noctalia/plugins.json";
    declared = {
      version = 2;
      states = {
        listener-level = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        wispr-status = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        solar-time = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        active-network = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
      };
    };
    modes = {
      "/version" = "always";
      "/states/listener-level" = "always";
      "/states/wispr-status" = "always";
      "/states/solar-time" = "always";
      "/states/active-network" = "always";
    };
  };

  xdg.configFile = {
    "noctalia/plugins/solar-time/manifest.json".source = ./noctalia-plugins/solar-time/manifest.json;
    "noctalia/plugins/solar-time/BarWidget.qml".source = ./noctalia-plugins/solar-time/BarWidget.qml;
    "noctalia/plugins/solar-time/SolarClock.js".source = ./noctalia-plugins/solar-time/SolarClock.js;
    "noctalia/plugins/active-network/manifest.json".source =
      ./noctalia-plugins/active-network/manifest.json;
    "noctalia/plugins/active-network/BarWidget.qml".source =
      ./noctalia-plugins/active-network/BarWidget.qml;
    "noctalia/plugins/active-network/StatusValidation.js".source =
      ./noctalia-plugins/active-network/StatusValidation.js;
  };

  xdg.dataFile = {
    "noctalia/plugins/wispr-status/plugin.toml".source = ./noctalia-plugins/wispr-status/plugin.toml;
    "noctalia/plugins/wispr-status/WisprStatusState.luau".source =
      ./noctalia-plugins/wispr-status/WisprStatusState.luau;
    "noctalia/plugins/wispr-status/WisprStatusService.luau".source = wisprStatusService;
    "noctalia/plugins/wispr-status/BarWidget.luau".source =
      ./noctalia-plugins/wispr-status/BarWidget.luau;
    "noctalia/plugins/listener-level/plugin.toml".source =
      ./noctalia-plugins/listener-level/plugin.toml;
    "noctalia/plugins/listener-level/level.luau".source = listenerLevelWidget;
    "noctalia/plugins/listener-level/TranscriptState.luau".source =
      ./noctalia-plugins/listener-level/TranscriptState.luau;
    "noctalia/plugins/listener-level/transcript-panel.luau".source = listenerTranscriptPanel;
  };

  services.mako = {
    enable = true;
    settings = {
      font = lib.mkForce "IosevkaTerm Nerd Font 11";
      background-color = lib.mkForce "${colors.base01}ee";
      text-color = lib.mkForce colors.base05;
      border-color = lib.mkForce "${colors.base02}aa";
      border-size = 2;
      border-radius = 12;
      padding = "12";
      margin = "8";
      width = 380;
      height = 120;
      default-timeout = 5000;
      layer = "overlay";
      anchor = "top-right";
      icons = true;
      icon-path = "";
      max-icon-size = 48;
      max-visible = 3;
      group-by = "app-name";

      "app-name=Listener" = {
        history = 0;
      };

      # Critical-urgency notifications get a longer timeout than the
      # 5s default so they're easier to catch when heads-down, but
      # never sticky-forever — every notification clears itself
      # eventually so the user doesn't accumulate a click-away queue.
      "urgency=critical" = {
        border-color = lib.mkForce "${colors.base08}cc";
        default-timeout = 30000;
      };

    };
  };
}
