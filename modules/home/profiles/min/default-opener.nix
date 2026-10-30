{
  config,
  lib,
  pkgs,
  user,
  horizon ? null,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  guard = config.criomosHome.remoteBuildCommandGuard;
  configuredForLowPowerNode = horizon != null && ((horizon.node.behavesAs or { }).lowPower or false);
  userPath =
    lib.optionalString guard.enable "${guard.directory}:"
    + "${config.home.homeDirectory}/.local/bin:$PATH";
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
  remoteBuildGuard =
    command:
    pkgs.writeShellScript command ''
      printf '%s\n' 'builds run on Prometheus through Nix'
      exit 1
    '';
in
{
  options.criomosHome.remoteBuildCommandGuard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = configuredForLowPowerNode;
      description = "Put laptop Rust build guards first in interactive and Flow child PATHs.";
    };
    directory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${config.home.homeDirectory}/.local/libexec/remote-build-command-guard";
      description = "The single declarative directory containing laptop Rust build guards.";
    };
  };

  config = lib.mkIf (sizeAtLeast "Min") {
    home = {
      sessionVariables.PATH = userPath;
      packages = [
        (lib.hiPrio desktopOpen)
        pkgs.handlr-regex
      ];
      file.".local/bin/xdg-open" = {
        source = "${desktopOpen}/bin/xdg-open";
        executable = true;
      };
      file.".local/libexec/remote-build-command-guard/cargo" = lib.mkIf guard.enable {
        source = remoteBuildGuard "cargo";
        executable = true;
      };
      file.".local/libexec/remote-build-command-guard/rustc" = lib.mkIf guard.enable {
        source = remoteBuildGuard "rustc";
        executable = true;
      };
    };

    xdg = {
      configFile."uwsm/env".text = ''
        export PATH="${lib.optionalString guard.enable "${guard.directory}:"}${config.home.homeDirectory}/.local/bin:''${PATH}"
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
