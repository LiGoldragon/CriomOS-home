{
  pkgs,
  lib,
  user,
  textScale,
  ...
}:
let
  darkScheme = ./ignis.yaml;
  lightScheme = ./ignis-light.yaml;

  # `textScale.fontPt` comes from `modules/home/text-scale.nix`
  # (single source of truth for the textSize ladder).
  inherit (textScale) fontPt;

  parseScheme =
    scheme:
    (lib.importJSON (
      pkgs.runCommand "base16-to-json"
        {
          nativeBuildInputs = [ pkgs.yq-go ];
        }
        ''
          yq -o=json '.' ${scheme} > $out
        ''
    )).palette;

  dark = parseScheme darkScheme;
  light = parseScheme lightScheme;

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

  /*
    OSC escape sequences for terminal color switching.
    Used by the zsh init hook below. Chroma persists the current mode;
    shells apply terminal colours for their own PTY at startup instead
    of a daemon broadcasting into every live /dev/pts entry.
  */
  mkOscSequence =
    c:
    let
      osc = n: color: ''\033]4;${toString n};${color}\007'';
    in
    ''
      ${osc 0 c.base00}${osc 1 c.base08}${osc 2 c.base0B}${osc 3 c.base0A}\
      ${osc 4 c.base0D}${osc 5 c.base0E}${osc 6 c.base0C}${osc 7 c.base05}\
      ${osc 8 c.base03}${osc 9 c.base08}${osc 10 c.base0B}${osc 11 c.base0A}\
      ${osc 12 c.base0D}${osc 13 c.base0E}${osc 14 c.base0C}${osc 15 c.base07}\
      \033]10;${c.base05}\007\033]11;${c.base00}\007\033]12;${c.base05}\007'';

  /*
    Shell hook: new terminals get correct colors + fzf theme.
    Reads the persisted mode written by Chroma's terminal concern
    (`$XDG_STATE_HOME/chroma/current-mode`).
  */
  darkOsc = mkOscSequence dark;
  lightOsc = mkOscSequence light;
  terminalInitHook = ''
    __chroma_init_theme() {
      local state="''${XDG_STATE_HOME:-$HOME/.local/state}/chroma"
      local mode
      mode=$(cat "$state/current-mode" 2>/dev/null) || return
      if [ "$mode" = "light" ]; then
        printf "${lightOsc}"
      else
        printf "${darkOsc}"
      fi
      [ -f "$state/fzf-theme.sh" ] && source "$state/fzf-theme.sh"
    }
    __chroma_init_theme
  '';

in
{
  config = {
    home = {
      username = user.name;
      homeDirectory = "/home/" + user.name;
      # stateVersion comes from the consumer (CriomOS userHomes.nix sets
      # it to 26.05); base.nix used to hardcode 25.05 which conflicted.
      packages = [
        # `theme-dark` / `theme-light` shell wrappers + the chroma
        # daemon + apply-script live in
        # modules/home/profiles/min/chroma.nix.
        pkgs.papirus-icon-theme
        pkgs.adw-gtk3
      ];
      file.".config/emacs-ignis-themes".source = emacsThemeDir;
    };

    gtk.enable = false;

    programs.zsh.initContent = lib.mkBefore terminalInitHook;

    stylix = {
      enable = true;
      autoEnable = true;
      polarity = "dark";
      base16Scheme = darkScheme;
      targets = {
        # Chroma switches terminal colors from its own state.
        emacs.enable = false;
        ghostty.enable = false;
        vscode.enable = false;
        wezterm.enable = false;
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
        # for ghostty/wezterm/vscode/emacs are off — those modules
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
