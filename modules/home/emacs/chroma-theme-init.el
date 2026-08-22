;;; chroma-theme-init.el --- Home-owned Chroma projection setup -*- lexical-binding: t; -*-

;; Ignis remains materialized by CriomOS-home.  The resident package owns only
;; the Chroma state projection and changes only these two concrete themes.
(let ((theme-dir (expand-file-name ".config/emacs-ignis-themes" "~")))
  (when (file-directory-p theme-dir)
    (add-to-list 'custom-theme-load-path theme-dir)))

(setq chroma-theme-light-theme 'ignis-light
      chroma-theme-dark-theme 'ignis-dark)
(require 'chroma-theme)
