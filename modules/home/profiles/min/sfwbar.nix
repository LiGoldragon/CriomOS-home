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
in
lib.mkIf behavesAs.edge {
  home.packages = [ pkgs.libnotify ];

  programs.noctalia = {
    enable = true;
    package = noctaliaShell;
    systemd.enable = false;
    settings = {
      idle = {
        pre_action_fade_seconds = 5.0;
        behavior = {
          screen-off = {
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
      bar.main = {
        start = [
          "launcher"
          "clock"
          "media"
        ];
        center = [ "workspaces" ];
        end = [
          "tray"
          "battery"
          "volume"
          "brightness"
          "control-center"
        ];
      };
    };
  };

  # Noctalia v5 replaced the old `programs.noctalia-shell` QML settings and
  # `plugins.json` model with `programs.noctalia`, TOML settings, and Luau
  # plugin manifests whose ids are shaped like `author/plugin:entry`. The old
  # listener-level QML widget cannot be carried forward as a safe compatibility
  # shim, so the v5 migration keeps the core bar and idle policy declarative and
  # leaves the Listener widget disabled until it is rewritten as a v5 plugin.

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
