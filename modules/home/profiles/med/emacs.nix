{
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (user) size;

  emacsBase = pkgs.emacs-pgtk;

  emacsWithPackages = (pkgs.emacsPackagesFor emacsBase).withPackages (
    epkgs: with epkgs; [
      # Modal editing
      xah-fly-keys
      multiple-cursors
      phi-search

      # Selector framework (vertico + companions)
      vertico
      vertico-prescient
      consult
      consult-flycheck
      consult-ghq
      embark
      embark-consult
      marginalia
      orderless
      prescient
      affe

      # Git
      magit
      forge
      magit-delta
      git-gutter
      git-link
      with-editor
      difftastic

      # Languages
      nix-ts-mode
      nixfmt
      nix-update
      rust-mode
      json-mode
      yaml-pro
      dockerfile-mode
      clojure-ts-mode
      haskell-mode

      # LSP / diagnostics
      eglot
      flycheck
      flycheck-eglot
      flycheck-clj-kondo
      flycheck-guile

      # Project navigation
      projectile
      find-file-in-project
      deadgrep
      justl
      zoxide
      ghq

      # Formatting
      format-all
      elisp-autofmt
      shfmt
      apheleia

      # Completion / docs
      company
      which-key
      eat
      helpful
      eldoc-box
      eros
      ob-async

      # Editing helpers
      lispy
      adaptive-wrap
      visual-fill-column

      # Project env
      envrc

      # Org / markdown
      org-roam
      poly-markdown

      # Auth (auth-source-pass is built into Emacs core)
      password-store

      # Theme
      base16-theme

      # Misc
      highlight-indentation
      eshell-prompt-extras
      ssh-deploy
      tokei
      visual-regexp-steroids
      ztree
      cider
      zprint-format

      # Common Lisp
      sly
      sly-macrostep
      sly-asdf
      sly-quicklisp

      # Tree-sitter grammars (cluster set)
      treesit-grammars.with-all-grammars
    ]
  );

  initEl = ''
    ;;; init.el — CriomOS-home Emacs (minimal port from criomos-archive).
    ;;; Lifted from criomos-archive/nix/{homeModule/emacs/init.el,
    ;;; pkdjz/mkEmacs/{packages,selector-common,vertico}.el} on 2026-05-06.
    ;;; aski / cozo / capnp tree-sitter, copilot/gptel/aidermacs, and
    ;;; niche packages were dropped per the 2026-05-06 minimal port.

    ;;; --- Built-in UI tweaks ---
    (tool-bar-mode -1)
    (menu-bar-mode -1)
    (scroll-bar-mode -1)
    (delete-selection-mode 1)
    (electric-pair-mode 1)
    (recentf-mode 1)
    (run-at-time nil (* 5 60) 'recentf-save-list)
    (set-face-attribute 'default nil :font "IosevkaTerm Nerd Font" :height 140)
    (custom-set-variables
     '(make-backup-files nil)
     '(recentf-max-menu-items 1024)
     '(recentf-max-saved-items 10024)
     '(inferior-lisp-program "sbcl")
     '(truncate-partial-width-windows nil)
     '(truncate-lines -1))

    ;;; --- Package configurations ---

    (use-package eat :defer t)
    (use-package apheleia)
    (use-package envrc :config (envrc-global-mode))

    (use-package eglot
     :custom (eglot-extend-to-xref t)
     :config
     (add-to-list 'eglot-server-programs '(nix-ts-mode . ("nil"))))

    (use-package flycheck-eglot
     :after (flycheck eglot)
     :config (global-flycheck-eglot-mode 1))

    (use-package highlight-indentation)

    (use-package nix-ts-mode
     :config
     (add-to-list 'auto-mode-alist '("\\.nix\\'" . nix-ts-mode)))

    (use-package nixfmt :hook (nix-ts-mode . nixfmt-on-save-mode))
    (use-package nix-update)
    (use-package justl)
    (use-package json-mode)

    (use-package yaml-pro
     :config
     (add-to-list 'auto-mode-alist '("\\.yaml\\'" . yaml-pro-ts-mode)))

    (use-package haskell-mode)

    (use-package treesit
     :custom (treesit-font-lock-level 4))

    (use-package rust-mode
     :custom (rust-mode-treesitter-derive t) (rust-format-on-save t))

    (use-package magit-delta :hook (magit-mode . magit-delta-mode))
    (use-package difftastic)

    (use-package with-editor
     :hook (eshell-mode . with-editor-export-editor))

    (use-package elisp-autofmt :before format-all)
    (use-package ssh-deploy)

    (use-package org-roam
     :config (org-roam-db-autosync-mode 1)
     :custom
     (org-roam-v2-ack t)
     (org-roam-directory "~/git/wiki")
     (org-roam-file-extensions '("md" "org"))
     (org-roam-capture-templates
      (list
       '("d" "default" plain ""
         :target
         (file+head
          "%<%Y%m%d%H%M%S-''${title}>.md"
          "---\ntitle: ''${title}\nid: %<%Y-%m-%dT%H%M%S>\ncategory: \n---\n")
         :unnarrowed t))))

    (use-package password-store)
    (use-package base16-theme)

    ;; Load ignis theme from darkman state at startup.
    (let ((theme-dir (expand-file-name ".config/emacs-ignis-themes" "~")))
      (when (file-directory-p theme-dir)
        (add-to-list 'custom-theme-load-path theme-dir)
        (let ((mode-file (expand-file-name "darkman/current-mode"
                           (or (getenv "XDG_STATE_HOME")
                               (expand-file-name ".local/state" "~")))))
          (when (file-readable-p mode-file)
            (let ((mode (string-trim (with-temp-buffer
                                       (insert-file-contents mode-file)
                                       (buffer-string)))))
              (pcase mode
                ("dark" (load-theme 'ignis-dark t))
                ("light" (load-theme 'ignis-light t))))))))

    (use-package clojure-ts-mode :custom (clojure-ts-ensure-grammars nil))

    (use-package flycheck-clj-kondo
     :hook
     ((clojure-ts-mode clojurescript-ts-mode clojurec-ts-mode)
      . flycheck-mode)
     :config
     (progn
       (flycheck-clj-kondo--define-checker
        clj-kondo-clj "clj" clojure-ts-mode "--cache")
       (flycheck-clj-kondo--define-checker
        clj-kondo-cljs "cljs" clojurescript-ts-mode "--cache")
       (flycheck-clj-kondo--define-checker
        clj-kondo-cljc "cljc" clojurec-ts-mode "--cache")
       (flycheck-clj-kondo--define-checker
        clj-kondo-edn "edn" clojure-ts-mode "--cache")
       (dolist (element
                '(clj-kondo-clj clj-kondo-cljs clj-kondo-cljc clj-kondo-edn))
         (add-to-list 'flycheck-checkers element))))

    (use-package cider)
    (use-package zprint-format)

    (use-package company
     :hook
     ((lisp-mode nix-ts-mode emacs-lisp-mode clojure-ts-mode rust-ts-mode)
      . company-mode))

    (use-package dockerfile-mode :mode "Dockerfile")

    (use-package xah-fly-keys
     :config
     (defun xfk-mentci-modify ()
       (xah-fly--define-keys
        xah-fly-command-map
        '(("~" . nil)
          (":" . nil)
          ("SPC" . xah-fly-leader-key-map)
          ("DEL" . xah-fly-leader-key-map)
          ("'" . xah-reformat-lines)
          ("," . xah-shrink-whitespaces)
          ("-" . xah-cycle-hyphen--space)
          ("." . backward-kill-word)
          (";" . xah-comment-dwim)
          ("/" . hippie-expand)
          ("\\" . nil)
          ("=" . nil)
          ("[" . xah-backward-punct)
          ("]" . xah-forward-punct)
          ("`" . other-frame)
          ("1" . xah-extend-selection)
          ("2" . xah-select-line)
          ("3" . delete-other-windows)
          ("4" . split-window-below)
          ("5" . delete-char)
          ("6" . xah-select-block)
          ("7" . xah-select-line)
          ("8" . xah-extend-selection)
          ("9" . xah-select-text-in-quote)
          ("0" . xah-pop-local-mark-ring)
          ("a" . execute-extended-command)
          ("b" . phi-search)
          ("K" . phi-search-backward)
          ("c" . previous-line)
          ("d" . xah-beginning-of-line-or-block)
          ("e" . xah-delete-left-char-or-selection)
          ("f" . undo)
          ("g" . backward-word)
          ("h" . backward-char)
          ("i" . xah-delete-current-text-block)
          ("j" . xah-copy-line-or-region)
          ("k" . xah-paste-or-paste-previous)
          ("l" . xah-insert-space-before)
          ("m" . xah-backward-left-bracket)
          ("n" . forward-char)
          ("o" . open-line)
          ("p" . kill-word)
          ("q" . xah-cut-line-or-region)
          ("r" . forward-word)
          ("s" . xah-end-of-line-or-block)
          ("t" . next-line)
          ("u" . xah-fly-insert-mode-activate)
          ("v" . xah-forward-right-bracket)
          ("w" . xah-next-window-or-frame)
          ("x" . consult-imenu)
          ("y" . set-mark-command)
          ("z" . xah-goto-matching-bracket)))
       (xah-fly--define-keys
        (define-prefix-command 'navigate-filesystem)
        '(("b" . consult-line)
          ("d" . deadgrep)
          ("h" . consult-buffer)
          ("t" . find-file-in-project)
          ("c" . projectile-switch-project)
          ("n" . magit-find-file)
          ("s" . find-file)))
       (xah-fly--define-keys
        (define-prefix-command 'multi-cursors)
        '(("b" . mc/mark-all-in-region-regexp)
          ("d" . mc/mark-all-like-this)
          ("h" . mc/mark-previous-like-this)
          ("c" . mc/cycle-backward)
          ("t" . mc/cycle-forward)
          ("n" . mc/mark-next-like-this)
          ("s" . mc/mark-all-dwim)
          ("g" . mc/skip-to-previous-like-this)
          ("r" . mc/skip-to-next-like-this)))
       (xah-fly--define-keys
        (define-prefix-command 'xah-fly-leader-key-map)
        '(("SPC" . xah-fly-insert-mode-activate)
          ("DEL" . xah-fly-insert-mode-activate)
          ("RET" . xah-fly-M-x)
          ("TAB" . xah-fly--tab-key-map)
          ("." . xah-fly-dot-keymap)
          ("'" . xah-fill-or-unfill)
          ("," . xah-fly-comma-keymap)
          ("-" . xah-show-formfeed-as-line)
          ("\\" . toggle-input-method)
          ("3" . delete-window)
          ("4" . split-window-right)
          ("5" . balance-windows)
          ("6" . xah-upcase-sentence)
          ("9" . ispell-word)
          ("a" . mark-whole-buffer)
          ("b" . end-of-buffer)
          ("c" . xah-fly-c-keymap)
          ("d" . beginning-of-buffer)
          ("e" . multi-cursors)
          ("f" . xah-search-current-word)
          ("g" . xah-close-current-buffer)
          ("h" . xah-fly-h-keymap)
          ("i" . kill-line)
          ("j" . xah-copy-all-or-region)
          ("k" . consult-yank-from-kill-ring)
          ("l" . recenter-top-bottom)
          ("m" . dired-jump)
          ("n" . xah-fly-n-keymap)
          ("o" . exchange-point-and-mark)
          ("p" . query-replace)
          ("q" . xah-cut-all-or-region)
          ("r" . xah-fly-r-keymap)
          ("s" . save-buffer)
          ("t" . xah-fly-t-keymap)
          ("u" . navigate-filesystem)
          ("w" . xah-fly-w-keymap)
          ("x" . xah-toggle-previous-letter-case)
          ("y" . xah-show-kill-ring))))
     (defun start-xah-fly-keys ()
       (xah-fly-keys 1)
       (xah-fly-keys-set-layout "colemak")
       (xfk-mentci-modify))
     (if (daemonp)
         (add-hook 'server-after-make-frame-hook 'start-xah-fly-keys)
       (start-xah-fly-keys))
     :custom (xah-fly-use-control-key nil))

    (use-package multiple-cursors :custom (mc/always-run-for-all t))

    (use-package auth-source-pass
     :config (auth-source-pass-enable)
     :custom (auth-sources '(password-store)))

    (use-package phi-search)
    (use-package poly-markdown)
    (use-package which-key :config (which-key-mode))
    (use-package deadgrep)
    (use-package forge :after (magit))
    (use-package magit :config (put 'magit-clean 'disabled nil))
    (use-package git-gutter :config (global-git-gutter-mode))

    (use-package projectile
     :config (projectile-mode +1)
     :custom (projectile-project-search-path '("~/git/" "/git/")))

    (use-package eshell-prompt-extras
     :config
     (with-eval-after-load "esh-opt"
       (autoload 'epe-theme-lambda "eshell-prompt-extras"))
     :custom
     (eshell-highlight-prompt nil)
     (eshell-prompt-function 'epe-theme-lambda))

    (use-package lispy :hook ((emacs-lisp-mode lisp-mode) . lispy-mode))

    (use-package adaptive-wrap
     :hook
     ((emacs-lisp-mode lisp-mode nix-ts-mode)
      . adaptive-wrap-prefix-mode))

    (use-package visual-fill-column
     :hook (markdown-mode . visual-fill-column-mode)
     :custom (visual-fill-column-width 80))

    (use-package find-file-in-project :custom (ffip-use-rust-fd t))
    (use-package git-link :custom (git-link-use-commit t))

    (use-package flycheck
     :custom
     (flycheck-idle-change-delay 7)
     (flycheck-idle-buffer-switch-delay 49)
     (flycheck-check-syntax-automatically '(save idle-change mode-enabled)))

    (use-package flycheck-guile
     :custom (geiser-default-implementation 'guile))

    (use-package ghq :commands ghq)
    (use-package shfmt :hook (sh-mode . shfmt-on-save-mode))
    (use-package sly)
    (use-package sly-macrostep)
    (use-package sly-asdf)
    (use-package sly-quicklisp)
    (use-package tokei)
    (use-package visual-regexp-steroids)

    (use-package zoxide
     :hook
     ((find-file projectile-after-switch-project) . zoxide-add))

    (use-package ztree)

    (use-package format-all
     :commands (format-all-mode format-all-buffer format-all-region-or-buffer)
     :hook
     ((prog-mode . format-all-mode)
      (markdown-mode . format-all-mode)
      (gfm-mode . format-all-mode))
     :init
     (setq format-all-formatters
           '(("Emacs Lisp" elisp-autofmt)
             ("Python" ruff)
             ("Shell" (shfmt "-i" "4" "-ci"))
             ("Markdown" mdformat)
             ("JSON" prettier "--parser" "json")
             ("YAML" prettier "--parser" "yaml")
             ("Clojure" zprint)))
     :config
     (define-format-all-formatter
      elisp-autofmt
      (:executable)
      (:install nil)
      (:languages "Emacs Lisp")
      (:features region)
      (:format
       (format-all--buffer-native
        'elisp-autofmt-mode
        (if region
            (lambda () (elisp-autofmt-region (car region) (cdr region)))
          (lambda () (elisp-autofmt-buffer))))))
     (define-format-all-formatter
      ruff
      (:executable "ruff")
      (:install nil)
      (:languages "Python")
      (:features)
      (:format
       (format-all--buffer-easy executable "format" "-")))
     (define-format-all-formatter
      mdformat
      (:executable "mdformat")
      (:install nil)
      (:languages "Markdown")
      (:features)
      (:format
       (format-all--buffer-easy executable "--wrap" "no" "-"))))

    ;;; --- Live evaluation helpers ---

    (use-package eros :hook (emacs-lisp-mode . eros-mode))

    (use-package helpful
     :bind
     (([remap describe-function] . helpful-function)
      ([remap describe-variable] . helpful-variable)
      ([remap describe-key] . helpful-key)))

    (use-package eldoc-box
     :hook (emacs-lisp-mode . eldoc-box-hover-mode))

    (use-package ob-async :after org)

    ;;; --- Selector framework (lifted from selector-common.el) ---

    (use-package affe
     :after (consult)
     :config
     (defun affe-orderless-regexp-compiler (input _type)
       (setq input (orderless-pattern-compiler input))
       (cons input (lambda (str) (orderless--highlight input str))))
     (setq affe-regexp-compiler #'affe-orderless-regexp-compiler))

    (use-package consult :custom (consult-preview-key "M-."))
    (use-package consult-flycheck)

    (use-package consult-ghq
     :after (consult)
     :custom
     (consult-ghq-find-function #'consult-find)
     (consult-ghq-grep-function #'consult-grep))

    (use-package embark)
    (use-package embark-consult)
    (use-package marginalia :config (marginalia-mode))

    (use-package orderless
     :config
     (defun flex-if-twiddle (pattern _index _total)
       (when (string-suffix-p "~" pattern)
         `(orderless-flex . ,(substring pattern 0 -1))))
     (defun without-if-bang (pattern _index _total)
       (cond
        ((equal "!" pattern)
         '(orderless-literal . ""))
        ((string-prefix-p "!" pattern)
         `(orderless-without-literal . ,(substring pattern 1)))))
     :custom
     (completion-styles '(orderless))
     (orderless-style-dispatchers '(flex-if-twiddle without-if-bang))
     (orderless-matching-styles '(orderless-regexp)))

    (use-package prescient :config (prescient-persist-mode +1))

    ;;; --- Vertico (lifted from vertico.el) ---

    (use-package vertico :config (vertico-mode))
    (use-package vertico-prescient :config (vertico-prescient-mode))

    ;;; init.el ends here.
  '';

  # Default-editor MIME types. The Emacs-shipped emacsclient.desktop
  # only declares a narrow C/C++/Pascal/TeX set; we register
  # emacsclient as the default for the cluster's full text / source
  # set. Text types not in this list still fall through to whichever
  # other registered .desktop matches (e.g. codium for some boutique
  # types), preserving chooser flexibility.
  defaultEditorMimeTypes = [
    "text/plain"
    "text/markdown"
    "text/x-markdown"
    "text/english"
    "text/x-makefile"
    "text/x-c"
    "text/x-c++"
    "text/x-c++hdr"
    "text/x-c++src"
    "text/x-chdr"
    "text/x-csrc"
    "text/x-java"
    "text/x-moc"
    "text/x-pascal"
    "text/x-tcl"
    "text/x-tex"
    "text/x-python"
    "text/x-rust"
    "text/x-go"
    "text/x-shellscript"
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
    "x-scheme-handler/org-protocol"
  ];

in
mkIf size.atLeastMed {
  programs.emacs = {
    enable = true;
    package = emacsWithPackages;
  };

  services.emacs = {
    enable = true;
    package = emacsWithPackages;
    startWithUserSession = "graphical";
  };

  home = {
    sessionVariables = {
      EDITOR = "emacsclient -c";
      VISUAL = "emacsclient -c";
    };
    file = {
      ".emacs.d/init.el".text = initEl;

      # User-local emacsclient.desktop with a full MIME list so the
      # xdg-open chooser offers it for markdown / python / rust / json /
      # yaml / nix / etc., not just the narrow set the Emacs package
      # ships. Wins over the package-shipped entry by being earlier in
      # XDG_DATA_DIRS. `Exec` uses the daemon-and-fallback form so a
      # missing daemon is not a hard error.
      ".local/share/applications/emacsclient.desktop".text = ''
        [Desktop Entry]
        Name=Emacs (Client)
        GenericName=Text Editor
        Comment=Edit text via emacsclient (daemon-attached)
        Exec=emacsclient -c -a emacs %F
        Icon=emacs
        Type=Application
        Terminal=false
        Categories=Development;TextEditor;
        StartupNotify=true
        StartupWMClass=Emacs
        Keywords=emacs;emacsclient;
        MimeType=${lib.concatStringsSep ";" defaultEditorMimeTypes};
        Actions=new-window;new-instance;

        [Desktop Action new-window]
        Name=New Window
        Exec=emacsclient -c -a emacs %F

        [Desktop Action new-instance]
        Name=New Instance
        Exec=emacs %F
      '';
    };

    # CLI tools the in-buffer formatters and language modes invoke.
    packages = with pkgs; [
      nil
      shfmt
      zprint
      ripgrep
      fd
    ];
  };

  xdg.mimeApps.defaultApplications = builtins.listToAttrs (
    map (mimeType: {
      name = mimeType;
      value = "emacsclient.desktop";
    }) defaultEditorMimeTypes
  );
}
