{
  lib,
  user,
  pkgs,
  ...
}:
let
  inherit (builtins) readFile toJSON;
  inherit (lib) optionalString optionals;

  tomlFormat = pkgs.formats.toml { };
  yamlFormat = pkgs.formats.yaml { };
  inherit (user) githubId;
  inherit (user) useColemak size;
  inherit (pkgs) mksh;

  tokenizedHub = pkgs.writeScriptBin "hub" ''
    #!${mksh}/bin/mksh
    export GITHUB_TOKEN=''${GITHUB_TOKEN:-''$(${pkgs.gopass}/bin/gopass show -o github.com/token)}
    export GITHUB_USER=''${GITHUB_USER:-''$(${pkgs.gopass}/bin/gopass show github.com/token login)}
    exec "${pkgs.hub}/bin/hub" "$@"
  '';

  tokenizedWrappedHub = pkgs.runCommand "hub" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.hub}/share $out/
    ln -s ${tokenizedHub}/bin/hub $out/bin/
  '';

  tokenizedGhCli = pkgs.writeScriptBin "gh" ''
    #!${mksh}/bin/mksh
    export GH_TOKEN=''${GITHUB_TOKEN:-''$(${pkgs.gopass}/bin/gopass show -o github.com/token)}
    exec "${pkgs.gh}/bin/gh" "$@"
  '';

  tokenizedWrappedGhCli = pkgs.runCommand "gh" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.gh}/share $out/
    ln -s ${tokenizedGhCli}/bin/gh $out/bin/
  '';

  lispDevPackages = with pkgs; [
    sbcl
  ];

  codingPackages =
    with pkgs;
    [
      qrencode
      jmtpfs
      # start('bash')
      nix-prefetch-git
      # start('pythonPackages')
      ranger
      # C/C++
      binutils
      openssh
      nginx
      sdcv # cli dictionary
      jq
      djvulibre
      #== go
      ghq
      elvish
      lf
      tokenizedWrappedHub
      tokenizedWrappedGhCli
      hugo
      #== rust
      watchexec
      zola
      git-series
      tree-sitter
      # Manuals
      unbound.man
    ];

  graphicalPackages = with pkgs; [
    ledger-live-desktop
    element-desktop
    telegram-desktop
    losslesscut-bin
  ];

in
lib.mkIf size.atLeastMed {
  programs = {
    starship = {
      enable = true;
      settings = {
        cmd_duration = {
          show_notifications = true;
          min_time_to_notify = 10000; # TODO('requires build flag')
        };
        git_status = {
          disabled = true;
        };
      };
    };
  };

  home = {
    packages =
      with pkgs;
      [
        # start('bash')
        taskwarrior3
        # start('pythonPackages')
        yt-dlp
        # ocrmypdf
        # C/C++
        imagemagick
        opus-tools
        mediainfo
        #== go
        gopass
        git-bug
        lazygit
        #== rust
        spotify-player
        # inputs.mentci.packages.${system}.mentci-codium — `inputs.mentci`
        # not declared in CriomOS-home flake; stale ref. Drop until the
        # mentci-tools flake actually exposes a mentci-codium attr.
      ]
      ++ graphicalPackages
      ++ codingPackages ++ lispDevPackages;

    file = {
      # ".config/jesseduffield/lazygit/config.yml".text = { };

      "gh/config.yml".text = toJSON {
        gitProtocol = "ssh";
      };

      ".config/rustfmt/rustfmt.toml".source = tomlFormat.generate "rustfmt.toml" {
        edition = "2021";
      };

      ".config/luaformatter/config.yaml".source = yamlFormat.generate "luaFormatterConfig.yaml" {
        indent_width = 2;
        continuation_indent_width = 2;
        align_args = false;
        align_parameter = false;
        align_table_field = false;
        spaces_inside_table_braces = true;
      };

      # start('pythonConfigs')
      ".config/youtube-dl/config".text = ''
        -f 'bestvideo[ext=webm]+bestaudio[ext=webm]/best[ext=webm]/best'
      '';

      ".config/ranger/rc.conf".text = '''' + (optionalString useColemak readFile ./colemak.conf);
      # end('pythonConfigs')

    };
  };

  # mentci-codium desktop entry + .claude.json MCP merge — both depend
  # on `inputs.mentci` which is not declared in CriomOS-home's flake.
  # Stale leftover. Drop until mentci-tools exposes the right surface.
}
