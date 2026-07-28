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

  /*
    Generate a base16 Emacs theme from a palette.
    Produces a -theme.el file that can be loaded with (load-theme 'ignis-dark t).
  */
  mkEmacsBase16Theme =
    { name, c }:
    pkgs.writeText "${name}-theme.el" ''
      (deftheme ${name} "Base16 ${name} theme.")
      (let ((class '((class color) (min-colors 89))))
        (custom-theme-set-faces
         '${name}
         `(default ((,class (:foreground "${c.base05}" :background "${c.base00}"))))
         `(cursor ((,class (:background "${c.base05}"))))
         `(region ((,class (:background "${c.base02}"))))
         `(highlight ((,class (:background "${c.base01}"))))
         `(hl-line ((,class (:background "${c.base01}"))))
         `(fringe ((,class (:background "${c.base01}"))))
         `(vertical-border ((,class (:foreground "${c.base02}"))))
         `(mode-line ((,class (:foreground "${c.base04}" :background "${c.base01}"))))
         `(mode-line-inactive ((,class (:foreground "${c.base03}" :background "${c.base01}"))))
         `(minibuffer-prompt ((,class (:foreground "${c.base0D}"))))
         `(font-lock-builtin-face ((,class (:foreground "${c.base0C}"))))
         `(font-lock-comment-face ((,class (:foreground "${c.base03}"))))
         `(font-lock-comment-delimiter-face ((,class (:foreground "${c.base03}"))))
         `(font-lock-constant-face ((,class (:foreground "${c.base09}"))))
         `(font-lock-doc-face ((,class (:foreground "${c.base03}"))))
         `(font-lock-function-name-face ((,class (:foreground "${c.base0D}"))))
         `(font-lock-keyword-face ((,class (:foreground "${c.base0E}"))))
         `(font-lock-negation-char-face ((,class (:foreground "${c.base08}"))))
         `(font-lock-preprocessor-face ((,class (:foreground "${c.base0A}"))))
         `(font-lock-string-face ((,class (:foreground "${c.base0B}"))))
         `(font-lock-type-face ((,class (:foreground "${c.base0A}"))))
         `(font-lock-variable-name-face ((,class (:foreground "${c.base08}"))))
         `(font-lock-warning-face ((,class (:foreground "${c.base08}"))))
         `(isearch ((,class (:foreground "${c.base00}" :background "${c.base0A}"))))
         `(lazy-highlight ((,class (:foreground "${c.base00}" :background "${c.base0C}"))))
         `(link ((,class (:foreground "${c.base0D}" :underline t))))
         `(link-visited ((,class (:foreground "${c.base0E}" :underline t))))
         `(button ((,class (:foreground "${c.base0D}" :underline t))))
         `(header-line ((,class (:foreground "${c.base05}" :background "${c.base01}"))))
         `(shadow ((,class (:foreground "${c.base03}"))))
         `(success ((,class (:foreground "${c.base0B}"))))
         `(warning ((,class (:foreground "${c.base0A}"))))
         `(error ((,class (:foreground "${c.base08}"))))
         `(outline-1 ((,class (:foreground "${c.base0D}"))))
         `(outline-2 ((,class (:foreground "${c.base0B}"))))
         `(outline-3 ((,class (:foreground "${c.base0C}"))))
         `(outline-4 ((,class (:foreground "${c.base0E}"))))
         `(outline-5 ((,class (:foreground "${c.base09}"))))
         `(outline-6 ((,class (:foreground "${c.base0A}"))))
         `(org-level-1 ((,class (:foreground "${c.base0D}"))))
         `(org-level-2 ((,class (:foreground "${c.base0B}"))))
         `(org-level-3 ((,class (:foreground "${c.base0C}"))))
         `(org-level-4 ((,class (:foreground "${c.base0E}"))))
         `(line-number ((,class (:foreground "${c.base03}" :background "${c.base01}"))))
         `(line-number-current-line ((,class (:foreground "${c.base05}" :background "${c.base01}"))))
         `(show-paren-match ((,class (:foreground "${c.base00}" :background "${c.base0D}"))))
         `(show-paren-mismatch ((,class (:foreground "${c.base00}" :background "${c.base08}"))))

         ;; Emacs 29+ tree-sitter faces
         `(font-lock-function-call-face ((,class (:foreground "${c.base0D}"))))
         `(font-lock-number-face ((,class (:foreground "${c.base09}"))))
         `(font-lock-operator-face ((,class (:foreground "${c.base0F}"))))
         `(font-lock-property-use-face ((,class (:foreground "${c.base08}"))))
         `(font-lock-punctuation-face ((,class (:foreground "${c.base04}"))))
         `(font-lock-bracket-face ((,class (:foreground "${c.base04}"))))
         `(font-lock-delimiter-face ((,class (:foreground "${c.base04}"))))
         `(font-lock-escape-face ((,class (:foreground "${c.base0C}"))))
         `(font-lock-misc-punctuation-face ((,class (:foreground "${c.base0F}"))))
         `(font-lock-variable-use-face ((,class (:foreground "${c.base05}"))))
         `(font-lock-regexp-face ((,class (:foreground "${c.base0B}"))))
         `(font-lock-regexp-grouping-construct ((,class (:foreground "${c.base0A}"))))
         `(font-lock-regexp-grouping-backslash ((,class (:foreground "${c.base0C}"))))))
      (provide-theme '${name})
    '';

  ignisDarkEmacsTheme = mkEmacsBase16Theme {
    name = "ignis-dark";
    c = dark;
  };
  ignisLightEmacsTheme = mkEmacsBase16Theme {
    name = "ignis-light";
    c = light;
  };

  emacsThemeDir = pkgs.runCommand "ignis-emacs-themes" { } ''
    mkdir -p $out
    cp ${ignisDarkEmacsTheme} $out/ignis-dark-theme.el
    cp ${ignisLightEmacsTheme} $out/ignis-light-theme.el
  '';

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

      activation.mergeCargoConfig = inputs.hexis.lib.mkManagedConfig {
        inherit lib pkgs hexis;
        file = "$HOME/.cargo/config.toml";
        declared = {
          build.jobs = 2;
        };
        modes = {
          "/build/jobs" = "always";
        };
      };
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
