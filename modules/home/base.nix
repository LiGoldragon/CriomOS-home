{
  config,
  pkgs,
  lib,
  inputs,
  hexis,
  user,
  constants,
  textScale,
  ...
}:
let
  # `textScale.fontPt` comes from `modules/home/text-scale.nix`
  # (single source of truth for the textSize ladder).
  inherit (textScale) fontPt;
  inherit (config.criomosHome) visualTheme;

  dark = config.lib.stylix.colors.withHashtag;
  light = (config.stylix.base16.mkSchemeAttrs visualTheme.lightBase16Scheme).withHashtag;

  emacsThemeDir = import ./emacs/ignis-themes.nix { inherit pkgs dark light; };

  redactNixStorePaths = pkgs.writeShellScriptBin "redact-nix-store-paths" ''
    exec ${pkgs.gnused}/bin/sed -E "s#/nix/store/[a-z0-9]{32}-[^[:space:]\"'<>)]*#/nix/store/<redacted>#g"
  '';

  nixProfileCompatibility = pkgs.callPackage ../../packages/nix-profile-compatibility { };

  /*
    Shell hook: new shells source Chroma's fzf state. Terminal
    colours are owned by terminal-native config paths, not by
    shell-startup OSC sequences.
  */
  terminalInitHook = ''
    __chroma_init_theme() {
      local state="''${XDG_STATE_HOME:-$HOME/.local/state}/chroma"
      [ -f "$state/fzf-theme.sh" ] && source "$state/fzf-theme.sh"
    }
    __chroma_init_theme

    with-nix-store-redaction() {
      "$@" > >(redact-nix-store-paths) 2> >(redact-nix-store-paths >&2)
    }
  '';

  ensuredHomeDirectories = constants.fileSystem.home.ensuredDirectories;

  ensuredHomeDirectoryCommands = lib.concatMapStringsSep "\n" (
    directory: ''${pkgs.coreutils}/bin/install -d "$HOME/${directory}"''
  ) ensuredHomeDirectories;

in
{
  config = {
    home = {
      username = user.name;
      homeDirectory = "/home/" + user.name;
      # stateVersion comes from the consumer (CriomOS userHomes.nix sets
      # it to 26.05); base.nix used to hardcode 25.05 which conflicted.
      packages = [
        # Chroma owns visual-state switching in
        # modules/home/profiles/min/chroma.nix.
        pkgs.papirus-icon-theme
        pkgs.adw-gtk3
        redactNixStorePaths
      ];
      file.".config/emacs-ignis-themes".source = emacsThemeDir;

      activation.ensureHomeDirectories = lib.hm.dag.entryAfter [
        "writeBoundary"
      ] ensuredHomeDirectoryCommands;

      activation.ensureNixProfileCompatibility = lib.hm.dag.entryBefore [ "installPackages" ] ''
        run ${nixProfileCompatibility}/bin/criomos-ensure-nix-profile-link
      '';

      activation.retireLocalCargoJobs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain.retireLegacyConfig}/bin/retire-managed-local-cargo-jobs "$HOME/.cargo/config.toml"
      '';
    };

    gtk.enable = false;

    programs.zsh.initContent = lib.mkBefore terminalInitHook;

    stylix = {
      enable = true;
      autoEnable = true;
      polarity = "dark";
      base16Scheme = visualTheme.darkBase16Scheme;
      targets = {
        # Chroma owns terminal-adjacent state and native app themes.
        emacs.enable = false;
        ghostty.enable = false;
        vscode.enable = false;
        wofi.enable = false;
        waybar.enable = false;
        fzf.enable = false;
        gtk.enable = false;
        gnome.enable = false;
      };
      image =
        pkgs.runCommand "wallpaper.png"
          {
            nativeBuildInputs = [ pkgs.imagemagick ];
          }
          ''
            magick -size 1920x1080 xc:${dark.base00} $out
          '';
      cursor = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 24;
      };
      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.iosevka-term;
          name = "IosevkaTerm Nerd Font";
        };
        sansSerif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Serif";
        };
        # All four font-size categories track the user's textSize
        # ladder (via the `textScale.fontPt` arg). Stylix targets
        # for ghostty/vscode/emacs are off — those modules
        # set fonts directly — but stylix-driven apps (waybar,
        # rofi/wofi, etc., when their targets are on) pick up the
        # right sizes from here.
        sizes = {
          terminal = fontPt;
          applications = fontPt;
          desktop = fontPt - 2;
          popups = fontPt - 2;
        };
      };
    };
  };
}
