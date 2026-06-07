{
  lib,
  pkgs,
  criomos-lib,
  user,
  horizon,
  config,
  inputs,
  rustToolchain,
  # Todo(data)
  ...
}:
let
  inherit (builtins) toJSON;
  inherit (lib)
    optionalAttrs
    optionalString
    optionals
    mkIf
    optional
    ;
  inherit (horizon) node;
  inherit (user)
    useColemak
    hasPubKey
    gitSigningKey
    matrixId
    size
    isMultimediaDev
    emailAddress
    ;
  inherit (user) githubId name;
  inherit (pkgs) writeText;

  homeDir = config.home.homeDirectory;

  fzfColemakBinds = import ./fzfColemak.nix;

  fzfBinds = (optionals useColemak fzfColemakBinds);

  mkFzfBinds = list: "--bind=" + (builtins.concatStringsSep "," list);

  fzfBindsString = optionalString (fzfBinds != [ ]) (mkFzfBinds fzfBinds);

  waylandQtpass = pkgs.qtpass.override { pass = waylandPass; };
  waylandPass = pkgs.pass.override {
    x11Support = false;
    waylandSupport = true;
  };

  desktopOpen = pkgs.writeShellScriptBin "xdg-open" ''
    exec ${pkgs.handlr-regex}/bin/handlr open "$@"
  '';

  fontPackages = with pkgs; [
    dejavu_fonts
    inter
    montserrat
    nerd-fonts.iosevka-term
    nerd-fonts.iosevka
    noto-fonts-color-emoji
  ];

  mkFcCache = pkgs.makeFontsCache { fontDirectories = fontPackages; };

  mkFontPaths = lib.concatMapStringsSep "\n" (path: "  <dir>${path}/share/fonts</dir>") fontPackages;

  mkFontConf = ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
    <fontconfig>
    ${mkFontPaths}
      <cachedir>${mkFcCache}</cachedir>
    </fontconfig>
  '';

  modernGraphicalPackages = with pkgs; [
    (lib.hiPrio desktopOpen)
    handlr-regex
    mpv
    # ctags
    swaylock
    grim
    slurp
    wayland-warpd
    zathura
    wl-clipboard
    libnotify
    imv
    wf-recorder
    libva-utils
    ffmpeg-full
    # start("GTK")
    gitg
    pwvucontrol # Pipewire audio GTK UI
    sonata
    dino
    # ptask # Broken
    transmission-remote-gtk
    # start("Qt")
    adwaita-qt
    qgnomeplatform
    waylandQtpass
    waylandPass
    crosspipe # Pipewire graph UI

    # TODO('horizon language')
    (pkgs.hunspell.withDicts (dicts: [
      dicts.en_GB-ize
      dicts.en_US
    ]))
    (aspellWithDicts (
      ds: with ds; [
        en
        en-computers
        en-science
      ]
    ))

  ];

  brootConfig = toJSON { };

  wayland-warpd = pkgs.warpd.override { withX = false; };

  leta = pkgs.callPackage ../../../../packages/leta { };

  unixUtilities =
    with pkgs;
    [
      dua # Disk usage
      lsof # List open files
      delta # Git diff viewew
      cpulimit # Limit a process' CPU usage
      yggdrasil
      usbutils
      pciutils
      efivar # Hardware
      lshw
      gptfdisk
      parted # Disk utils
      wireguard-tools
    ]
    ++ (optionals (node.machine.arch == "x86-64") [ i7z ]);

  programmingTools = with pkgs; [
    # C
    stdenv.cc
    # Rust
    rustToolchain
    # Agent language intelligence
    leta
    typescript-language-server
    typescript
    gopls
    clang-tools
    ast-grep
    tree-sitter
    # Nix
    nil
    nixfmt
    npins
    # Clojure
    clojure
    babashka
    neil
    clj-kondo
    leiningen
    cljfmt
    # lisp
    zprint
    # Python
    python3
    ruff
    # Flashing
    avrdude
    # Shell
    shfmt
    # Other
    meld # GTK diff editor
    gg-jj # Jujutsu GUI
    lazyjj # # jujutsu TUI
    just
    difftastic
    tokei # Lines of code
    scc # Structured code counts
  ];

  unixDeveloperPackages = unixUtilities ++ programmingTools;

  deploymentPackages = with pkgs; [
    inputs.lojix-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
    (pkgs.callPackage ../../../../packages/lojix-run { inherit inputs; })
    age
    sops
    ssh-to-age
  ];

  # pi-mentci wrapper dropped 2026-04-25; pi itself returns 2026-04-29
  # built directly from inputs.pi-src via packages/pi/default.nix.
  AIPackages = [
    pkgs.gemini-cli
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.opencode
    pkgs.llama-cpp
    (pkgs.callPackage ../../../../packages/gws { inherit inputs; })
    (pkgs.callPackage ../../../../packages/pi { inherit inputs; })
    (pkgs.callPackage ../../../../packages/playwright-cli { })
  ];

  nixpkgsPackages =
    with pkgs;
    [
      mksh # saner bash
      retry
      ncpamixer
      flac
      shntool
      dvtm
      abduco # Multiplexer/session
      vis # regex Editor
      tree
      ncdu # File visualizing
      unzip
      unrar
      fuse
      cryptsetup
      # Network
      sshfs-fuse
      ifmetric
      curl
      wget
      transmission_4
      tremc
      aria2 # multi-protocol download
      rsync
      nload
      nmap
      iftop
      # Wireless
      iw
      wirelesstools
      acpi
      sox # audio capture
      tio # serial tty
      androidenv.androidPkgs.platform-tools # adb/fastboot
      #== rust
      sd
      ripgrep
      fd
      eza
      bat
      broot
      eva # tui calculator
    ]
    ++ modernGraphicalPackages # (Todo configure)
    ++ unixDeveloperPackages
    ++ (optionals isMultimediaDev (
      with pkgs;
      [
        inkscape
      ]
    ));

  nordvpnSeed = pkgs.writeScriptBin "nordvpn-seed" ''
    #!${pkgs.mksh}/bin/mksh
    GOPASS_PATH="nordaccount.com/API-Key"
    KEY_FILE="/etc/nordvpn/privateKey"
    API="https://api.nordvpn.com/v1/users/services/credentials"

    if [ $# -ge 1 ]; then
      TOKEN="$1"
    else
      TOKEN=$(${pkgs.gopass}/bin/gopass show -o "$GOPASS_PATH" 2>/dev/null)
      if [ -z "$TOKEN" ]; then
        print -u2 "no token at gopass path: $GOPASS_PATH"
        exit 1
      fi
    fi

    KEY=$(${pkgs.curl}/bin/curl -sf -u "token:''${TOKEN}" "$API" \
      | ${pkgs.jq}/bin/jq -r .nordlynx_private_key)

    if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then
      print -u2 "failed to derive WireGuard private key from API"
      exit 1
    fi

    print "$KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    print "seeded $KEY_FILE"
  '';

  # nightshift + brightness shell wrappers retired — the chroma
  # daemon (modules/home/profiles/min/chroma.nix) now owns the
  # warmth and brightness axes. Kept until the daemon's
  # CLI / apply path was wired into the dispatcher; archive
  # incident `a415e3e` (zeus 2026-04-26, the systemd cycle that
  # the nightshift-sync chain produced) is what motivated the
  # consolidation.

in
mkIf size.min {
  fonts.fontconfig = {
    enable = true;
    # TODO
    defaultFonts = {
      monospace = [ ];
      sansSerif = [ ];
      serif = [ ];
      emoji = [ ];
    };
  };

  services = {
    dunst = {
      enable = !size.min;
      settings = {
        global = {
          geometry = "300x5-30+50";
          transparency = 10;
        };

        urgency_normal = {
          timeout = 10;
        };
      };
    };

    gpg-agent = {
      enable = true;
      verbose = true;
      pinentry.package = pkgs.pinentry-gnome3;
      defaultCacheTtl = 10800;
      maxCacheTtl = 86400;
      defaultCacheTtlSsh = 3600;
      maxCacheTtlSsh = 86400;
      enableSshSupport = true;
      sshKeys = (optional hasPubKey user.pubKeys.${node.name}.keygrip);
    };

    mpd = {
      enable = true;
      musicDirectory = "~/Music";
    };

    pueue = {
      enable = true;
      settings = {
        shared = { };
        client = {
          dark_mode = config.stylix.polarity == "dark";
        };
        daemon = {
          default_parallel_tasks = 1;
        };
      };
    };

    # swaync disabled — noctalia handles notifications natively
    swaync.enable = false;
  };

  programs = {
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
      };
    };

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    ghostty = {
      enable = true;
      installVimSyntax = true;
    };

    fzf = {
      enable = true;
      defaultCommand = "fd --type f";
      defaultOptions = [ fzfBindsString ];
    };

    git = {
      enable = true;
      signing = mkIf hasPubKey {
        key = gitSigningKey;
        signByDefault = true;
      };
      settings = {
        user.email = emailAddress;
        user.name = name;
        pull.rebase = true;
        init.defaultBranch = "main";
        github.user = githubId;
        ghq.root = "/git";
        hub.protocol = "ssh";
        # gas-city's bd-init script does `git config --global beads.role
        # maintainer` if unset. ~/.config/git/config is read-only (this
        # very file), so the write fails. Pre-set it declaratively so
        # the script's check passes without writing.
        beads.role = "maintainer";
      };
    };

    gpg = {
      enable = true;
      settings = { };
    };

    joshuto = {
      enable = true;
    };

    jujutsu = {
      enable = true;
      settings = {
        ui = {
          diff-instructions = false;
          diff-formatter = [
            "difft"
            "--color=always"
            "$left"
            "$right"
          ];
          # Editor fallback ABORTS instead of blocking on an interactive
          # editor. Every description-taking jj invocation must use
          # -m '<msg>' inline. Per psyche 2026-05-26 (intent record 808)
          # and skills/jj.md §"Descriptionless commits are forbidden".
          # Subagents repeatedly tripped on emacsclient blocking; the
          # /false/ shim exits non-zero so jj surfaces a clear failure
          # instead of waiting indefinitely.
          editor = "false";
        };
        user = {
          name = name;
          email = emailAddress;
        };
        signing = mkIf hasPubKey {
          behavior = "own";
          backend = "gpg";
          key = gitSigningKey;
        };
      };
    };

    lapce = {
      enable = true;
      plugins = [ ];
      settings = {
        core = {
          modal = true;
          color-theme = if config.stylix.polarity == "dark" then "Lapce Dark" else "Lapce Light";
        };
        editor = {
          font-family = "Iosevka Nerd Font";
          font-size = 16;
          bracket-pair-colorization = true;
          highlight-matching-brackets = true;
        };
        ui = {
          open-editors-visible = false;
          font-size = 14;
        };
      };
    };

    bottom = {
      enable = true;
      settings = { };
    };

    starship = {
      enable = true;
    };

    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      history = {
        ignoreDups = true;
        expireDuplicatesFirst = true;
      };

      defaultKeymap = "viins";

      sessionVariables = {
        RSYNC_OLD_ARGS = 1;
        QT_QPA_PLATFORM = "wayland";
      };

      shellAliases = {
        tsync = "rsync --progress --recursive";
        nsync = "rsync --checksum --progress --recursive";
        dsync = "rsync --checksum --progress --recursive --delete";
      };

      initContent =
        builtins.readFile ../../nonNix/zshrc
        + ''
          if [[ $options[zle] = on ]]; then
          . ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.zsh
          fi
        ''
        + (optionalString useColemak (builtins.readFile ../../nonNix/colemak.zsh));
    };

    wofi = {
      enable = true;
    };

    zoxide.enable = true;
  };

  home = {
    sessionVariables = {
      ENABLE_CLAUDEAI_MCP_SERVERS = "false";
    };

    packages =
      fontPackages
      ++ nixpkgsPackages
      ++ deploymentPackages
      ++ AIPackages
      ++ [
        nordvpnSeed
        pkgs.wl-gammarelay-rs
        # chroma daemon + CLI live in the chroma module
        # (modules/home/profiles/min/chroma.nix); it owns the
        # warmth + brightness paths now.
      ];

    file = {
      ".local/bin/xdg-open" = {
        source = "${desktopOpen}/bin/xdg-open";
        executable = true;
      };

      ".config/IJHack/QtPass.conf".text = ''
        [General]
        autoclearSeconds=20
        passwordLength=32
        useTrayIcon=false
        hideContent=false
        hidePassword=true
        clipBoardType=1
        hideOnClose=false
        passExecutable=${waylandPass}/bin/pass
        passTemplate=login\nurl
        pwgenExecutable=${pkgs.pwgen}/bin/pwgen
        startMinimized=false
        templateAllFields=false
        useAutoclear=true
        useTrayIcon=false
        version=${pkgs.qtpass.version}
      '';

      ".config/broot/conf.toml".text = brootConfig;
    };
  };

  # programs.pi-mentci block dropped 2026-04-25 — pi-mentci itself
  # dropped from CriomOS-home flake.nix inputs.

  systemd = {
    user.services = {
      wl-gammarelay-rs = {
        Unit = {
          Description = "DBus interface for display temperature, brightness and gamma control";
          PartOf = [ "graphical-session.target" ];
          # `graphical-session-pre.target` rather than `.target`:
          # avoids the cycle that the (now-retired) nightshift-sync
          # chain produced — see archive incident a415e3e
          # (2026-04-26 zeus). chroma-daemon is `After =
          # wl-gammarelay-rs.service`, which keeps the dependency
          # graph walking one direction only.
          After = [ "graphical-session-pre.target" ];
        };
        Service = {
          ExecStart = "${pkgs.wl-gammarelay-rs}/bin/wl-gammarelay-rs";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # The three nightshift-* services and the brightness shell
      # were retired when chroma landed; the daemon owns those
      # paths now. See modules/home/profiles/min/chroma.nix.
    };
  };

  xdg = {
    configFile = {
      "fontconfig/conf.d/10-CriomOS-fonts-paths.conf".text = mkFontConf;

      "uwsm/env".text = ''
        export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"
        export NIXOS_OZONE_WL=1
        export QT_QPA_PLATFORM=wayland
        export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
        export GDK_BACKEND=wayland
        export SDL_VIDEODRIVER=wayland
        export MOZ_ENABLE_WAYLAND=1
        export _JAVA_AWT_WM_NONREPARENTING=1
      '';
    };

    configFile."handlr/handlr.toml".text = ''
      expand_wildcards = true
    '';

    mimeApps = {
      enable = true;
      defaultApplications =
        let
          defaultBrowser = "chromium.desktop";
          defaultMailer = "evolution.desktop";
          defaultAudioPlayer = "mpv.desktop";
        in
        {
          "audio/x-m4b" = defaultAudioPlayer;
          "application/zip" = "org.gnome.FileRoller.desktop";

          "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
          "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";

          "application/epub+zip" = "calibre-ebook-viewer.desktop";
          "application/pdf" = "org.pwmt.zathura-pdf-mupdf.desktop";

          "text/html" = defaultBrowser;
          "x-scheme-handler/http" = defaultBrowser;
          "x-scheme-handler/https" = defaultBrowser;
          "x-scheme-handler/ftp" = defaultBrowser;
          "x-scheme-handler/chrome" = defaultBrowser;
          "application/x-extension-htm" = defaultBrowser;
          "application/x-extension-html" = defaultBrowser;
          "application/x-extension-shtml" = defaultBrowser;
          "application/xhtml+xml" = defaultBrowser;
          "application/x-extension-xhtml" = defaultBrowser;
          "application/x-extension-xht" = defaultBrowser;

          "x-scheme-handler/about" = defaultBrowser;
          "x-scheme-handler/unknown" = defaultBrowser;

          "x-scheme-handler/mailto" = defaultMailer;
          "x-scheme-handler/news" = defaultMailer;
          "x-scheme-handler/snews" = defaultMailer;
          "x-scheme-handler/nntp" = defaultMailer;
          "x-scheme-handler/feed" = defaultMailer;
          "message/rfc822" = defaultMailer;
          "application/rss+xml" = defaultMailer;
          "application/x-extension-rss" = defaultMailer;
        };
    };

  };
}
