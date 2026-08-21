{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (user) size;
  defaultBrowser = "google-chrome.desktop";
  browserMimeTypes = [
    "text/html"
    "x-scheme-handler/http"
    "x-scheme-handler/https"
    "x-scheme-handler/ftp"
    "x-scheme-handler/chrome"
    "application/x-extension-htm"
    "application/x-extension-html"
    "application/x-extension-shtml"
    "application/xhtml+xml"
    "application/x-extension-xhtml"
    "application/x-extension-xht"
    "x-scheme-handler/about"
    "x-scheme-handler/unknown"
  ];
  desktopOpen = pkgs.writeShellScriptBin "xdg-open" ''
    exec ${pkgs.handlr-regex}/bin/handlr open "$@"
  '';
in
{
  config = lib.mkIf size.min {
    home = {
      sessionVariables.PATH = "${config.home.homeDirectory}/.local/bin:$PATH";
      packages = [
        (lib.hiPrio desktopOpen)
        pkgs.handlr-regex
      ];
      file.".local/bin/xdg-open" = {
        source = "${desktopOpen}/bin/xdg-open";
        executable = true;
      };
    };

    xdg = {
      configFile."uwsm/env".text = ''
        export PATH="${config.home.homeDirectory}/.local/bin:''${PATH}"
        export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"
        export XDG_SESSION_DESKTOP=niri
        export NIXOS_OZONE_WL=1
        export ELECTRON_OZONE_PLATFORM_HINT=wayland
        export QT_QPA_PLATFORM=wayland
        export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
        export GDK_BACKEND=wayland
        export SDL_VIDEODRIVER=wayland
        export MOZ_ENABLE_WAYLAND=1
        export _JAVA_AWT_WM_NONREPARENTING=1
      '';

      mimeApps = {
        enable = true;
        defaultApplications = builtins.listToAttrs (
          map (mimeType: {
            name = mimeType;
            value = defaultBrowser;
          }) browserMimeTypes
        );
      };
    };
  };
}
