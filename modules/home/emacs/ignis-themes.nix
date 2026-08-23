{ pkgs, dark, light }:
let
  # This is the shared generator and materializer for Home's resident Ignis
  # themes.  The projection witness imports it too, so its themes are the
  # actual Home artefacts rather than test-only lookalikes.
  mkEmacsBase16Theme =
    { name, c }:
    pkgs.writeText "${name}-theme.el" ''
      (deftheme ${name} "Base16 ${name} theme.")
      (let ((class t))
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

  darkTheme = mkEmacsBase16Theme { name = "ignis-dark"; c = dark; };
  lightTheme = mkEmacsBase16Theme { name = "ignis-light"; c = light; };
in
pkgs.runCommand "ignis-emacs-themes" { } ''
  mkdir -p $out
  cp ${darkTheme} $out/ignis-dark-theme.el
  cp ${lightTheme} $out/ignis-light-theme.el
''
