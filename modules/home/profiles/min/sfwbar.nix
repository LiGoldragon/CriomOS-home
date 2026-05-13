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
in
lib.mkIf behavesAs.edge {
  programs.noctalia-shell = {
    enable = true;
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
          { id = "MediaMini"; }
        ];
        center = [
          { id = "Workspace"; }
        ];
        right = [
          { id = "plugin:whisrs-level"; }
          {
            id = "Tray";
            colorizeIcons = false;
            drawerEnabled = true;
            hidePassive = false;
            pinned = [ "whisrs*" ];
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
        whisrs-level = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
      };
    };
    modes = {
      "/version" = "always";
      "/states/whisrs-level" = "always";
    };
  };

  xdg.configFile = {
    "noctalia/plugins/whisrs-level/manifest.json".source =
      ./noctalia-plugins/whisrs-level/manifest.json;
    "noctalia/plugins/whisrs-level/BarWidget.qml".source =
      ./noctalia-plugins/whisrs-level/BarWidget.qml;
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
