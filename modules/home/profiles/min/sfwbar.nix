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
  noctaliaShell =
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [
          ./noctalia-patches/niri-title-only-updates.patch
        ];
      });
in
lib.mkIf behavesAs.edge {
  home.packages = [ pkgs.libnotify ];

  programs.noctalia-shell = {
    enable = true;
    package = noctaliaShell;
    systemd.enable = false;
    settings = {
      idle = {
        enabled = true;
        screenOffTimeout = 300;
        lockTimeout = 3600;
        suspendTimeout = 0;
        fadeDuration = 5;
      };
      bar.widgets = {
        left = [
          { id = "Launcher"; }
          { id = "Clock"; }
          { id = "plugin:solar-time"; }
          { id = "MediaMini"; }
        ];
        center = [
          { id = "Workspace"; }
        ];
        right = [
          { id = "plugin:listener-level"; }
          {
            id = "Tray";
            colorizeIcons = false;
            drawerEnabled = true;
            hidePassive = false;
          }
          {
            id = "Battery";
            displayMode = "graphic";
          }
          { id = "Volume"; }
          { id = "Brightness"; }
          { id = "ControlCenter"; }
        ];
      };
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
        solar-time = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
      };
    };
    modes = {
      "/version" = "always";
      "/states/listener-level" = "always";
      "/states/solar-time" = "always";
    };
  };

  xdg.configFile = {
    "noctalia/plugins/listener-level/manifest.json".source =
      ./noctalia-plugins/listener-level/manifest.json;
    "noctalia/plugins/listener-level/BarWidget.qml".source =
      ./noctalia-plugins/listener-level/BarWidget.qml;
    "noctalia/plugins/solar-time/manifest.json".source = ./noctalia-plugins/solar-time/manifest.json;
    "noctalia/plugins/solar-time/BarWidget.qml".source = ./noctalia-plugins/solar-time/BarWidget.qml;
    "noctalia/plugins/solar-time/SolarClock.js".source = ./noctalia-plugins/solar-time/SolarClock.js;
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
