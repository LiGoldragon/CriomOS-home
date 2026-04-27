{
  pkgs,
  lib,
  user,
  inputs,
  criomos-lib,
  ...
}:
let
  inherit (user) size;
  inherit (criomos-lib) mkJsonMerge;

  system = pkgs.stdenv.hostPlatform.system;

  visualjj = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "visualjj";
      publisher = "visualjj";
      version = "0.27.0";
    };
    vsix = pkgs.fetchurl {
      name = "visualjj-0.27.0-linux-x64.vsix";
      url = "https://open-vsx.org/api/visualjj/visualjj/linux-x64/0.27.0/file/visualjj.visualjj-0.27.0@linux-x64.vsix";
      hash = "sha256-4w/A3C9WWfKbZF3LnaLR9aZ78hvU+lrEXS8nnMbgzeA=";
    };
    postInstall = ''
      jj=$out/share/vscode/extensions/visualjj.visualjj/dist/bin/jj
      if [ -f "$jj" ]; then
        ${pkgs.patchelf}/bin/patchelf \
          --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
          --set-rpath "${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}" \
          "$jj"
      fi
    '';
  };

  ovsx = inputs.nix-vscode-extensions.extensions.${system}.open-vsx;

  # All aski-related code dropped per Li 2026-04-25.

  nixSettings = {
    # Theme — stylix generates base16 theme, darkman switches via portal
    "window.autoDetectColorScheme" = true;
    "workbench.preferredDarkColorTheme" = "Default Dark Modern";
    "workbench.preferredLightColorTheme" = "Default Light Modern";

    # jj uses git as backend — VSCode's SCM API surface assumes vscode.git is available,
    # so we keep it enabled for extensions that read VCS state (vscode-pi, etc).
    # VisualJJ colocates in the same SCM panel for the actual jj workflow.
    "git.enabled" = true;
    "git.autoRepositoryDetection" = true;
    "visualjj.showSourceControlColocated" = true;

    # direnv — auto-reload on .envrc change
    "direnv.restart.automatic" = true;

    # Nix
    "nix.enableLanguageServer" = true;

    # Terminal
    "terminal.integrated.defaultProfile.linux" = "zsh";

    # Suppress welcome tab and extension walkthroughs
    "workbench.startupEditor" = "none";
    "workbench.welcomePage.walkthroughs.openOnInstall" = false;

    # Extensions managed by Nix — no marketplace updates
    "extensions.autoUpdate" = false;
    "extensions.autoCheckUpdates" = false;

    # Telemetry off
    "telemetry.telemetryLevel" = "off";
    "update.mode" = "none";

    # Editor
    "window.openFilesInNewWindow" = "default";
    "editor.renderWhitespace" = "boundary";
    "editor.minimap.enabled" = false;
    "files.trimTrailingWhitespace" = true;
    "files.insertFinalNewline" = true;
  };

in
lib.mkIf size.atLeastMed {

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;

    profiles.default = {
      extensions = [
        visualjj
        ovsx.anthropic.claude-code
        ovsx.google.geminicodeassist
        ovsx.openai.chatgpt
        ovsx.cdervis.vscode-pi
        pkgs.vscode-extensions.mkhl.direnv
        pkgs.vscode-extensions.jnoortheen.nix-ide
      ];
    };
  };

  home.sessionVariables = {
    EDITOR = lib.mkForce "codium --wait";
    VISUAL = lib.mkForce "codium --wait";
  };

  xdg.mimeApps.defaultApplications = builtins.listToAttrs (map (t: {
    name = t;
    value = "codium.desktop";
  }) [
    "text/plain"
    "text/markdown"
    "text/x-markdown"
    "text/x-python"
    "text/x-shellscript"
    "text/x-c"
    "text/x-c++"
    "text/x-rust"
    "text/x-go"
    "text/x-java"
    "text/x-toml"
    "text/x-nix"
    "text/x-lua"
    "text/x-diff"
    "text/x-log"
    "text/csv"
    "text/xml"
    "application/json"
    "application/x-yaml"
    "application/xml"
    "application/toml"
    "application/x-shellscript"
  ]);

  home.activation.mergeVscodiumSettings = mkJsonMerge {
    inherit lib pkgs;
    file = "$HOME/.config/VSCodium/User/settings.json";
    inherit nixSettings;
  };
}
