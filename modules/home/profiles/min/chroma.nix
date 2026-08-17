{
  config,
  pkgs,
  lib,
  inputs,
  user,
  horizon,
  textScale,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (horizon.node) behavesAs;
  inherit (user) size;
  inherit (textScale) fontPt;
  inherit (config.criomosHome) visualTheme;
  inherit (visualTheme) darkThemeSwitchTiming lightThemeSwitchTiming;

  chromaPackage = inputs.chroma.packages.${pkgs.stdenv.hostPlatform.system}.default;

  dark = config.lib.stylix.colors.withHashtag;
  light = (config.stylix.base16.mkSchemeAttrs visualTheme.lightBase16Scheme).withHashtag;

  mkChromaPalette = name: colors: ''
    (${name}
      (Base00 ${colors.base00})
      (Base01 ${colors.base01})
      (Base02 ${colors.base02})
      (Base03 ${colors.base03})
      (Base04 ${colors.base04})
      (Base05 ${colors.base05})
      (Base06 ${colors.base06})
      (Base07 ${colors.base07})
      (Base08 ${colors.base08})
      (Base09 ${colors.base09})
      (Base0A ${colors.base0A})
      (Base0B ${colors.base0B})
      (Base0C ${colors.base0C})
      (Base0D ${colors.base0D})
      (Base0E ${colors.base0E})
      (Base0F ${colors.base0F}))
  '';

  darkPalette = mkChromaPalette "Dark" dark;
  lightPalette = mkChromaPalette "Light" light;

  mkGhosttyPaletteLines =
    {
      colors,
      black ? colors.base00,
    }:
    lib.concatStringsSep "\n" [
      "palette = 0=${black}"
      "palette = 1=${colors.base08}"
      "palette = 2=${colors.base0B}"
      "palette = 3=${colors.base0A}"
      "palette = 4=${colors.base0D}"
      "palette = 5=${colors.base0E}"
      "palette = 6=${colors.base0C}"
      "palette = 7=${colors.base05}"
      "palette = 8=${colors.base03}"
      "palette = 9=${colors.base08}"
      "palette = 10=${colors.base0B}"
      "palette = 11=${colors.base0A}"
      "palette = 12=${colors.base0D}"
      "palette = 13=${colors.base0E}"
      "palette = 14=${colors.base0C}"
      "palette = 15=${colors.base07}"
    ];

  mkGhosttyConfig =
    {
      name,
      colors,
      light ? false,
    }:
    let
      ghosttyPaletteLines = mkGhosttyPaletteLines {
        inherit colors;
        black = if light then colors.base05 else colors.base00;
      };
    in
    pkgs.writeText "ghostty-${name}.conf" ''
      font-family = IosevkaTerm Nerd Font
      font-size = ${toString fontPt}
      window-decoration = false
      gtk-titlebar = false
      window-theme = ghostty
      background = ${colors.base00}
      foreground = ${colors.base05}
      cursor-color = ${colors.base05}
      selection-background = ${colors.base02}
      selection-foreground = ${colors.base05}
      ${ghosttyPaletteLines}
    '';

  ghosttyDarkConfig = mkGhosttyConfig {
    name = "dark";
    colors = dark;
  };
  ghosttyLightConfig = mkGhosttyConfig {
    name = "light";
    colors = light;
    light = true;
  };

  defaultConfig = ''
    (Config
      (Theme
        (Concerns Terminal Desktop Ghostty Emacs Pi)
        (Palettes
    ${darkPalette}
    ${lightPalette})
        (Adapters
          (Dconf ${pkgs.dconf}/bin/dconf)
          (Emacsclient ${pkgs.emacs-pgtk}/bin/emacsclient))
        (FontPointSize ${toString fontPt})
        (GhosttyConfigTemplates
          (Dark ${ghosttyDarkConfig})
          (Light ${ghosttyLightConfig}))
        (PiThemeControl
          (RegistryDirectory (RuntimeRelative chroma/pi-live-theme.d))
          (ConnectTimeoutMillis 100)
          (WriteTimeoutMillis 100))
        (Schedule
          (Waypoint (Sunrise ${lightThemeSwitchTiming}) Light)
          (Waypoint (Sunset ${darkThemeSwitchTiming}) Dark)
          (Default Dark)))
      (Warmth
        (Schedule
          (Waypoint (CivilDawn (SignedMinutes -30))
                    (Level Cold)
                    (Ramp (Minutes 30)))
          (Waypoint (CivilDusk (SignedMinutes -60))
                    (Level Warmest)
                    (Ramp (Minutes 60)))
          (Default Neutral)))
      (Brightness
        (Schedule (Manual Bright))))
  '';

in
mkIf (size.min && behavesAs.edge) {
  assertions = [
    {
      assertion = light.base05 != light.base00;
      message = "Chroma Ghostty light theme requires readable ANSI black for Codex key hints.";
    }
  ];

  home.packages = [
    chromaPackage
    pkgs.dconf
  ];

  systemd.user.services.chroma-daemon = {
    Unit = {
      Description = "Chroma — visual-state daemon (theme + warmth + brightness)";
      After = [
        "graphical-session-pre.target"
        "wl-gammarelay-rs.service"
      ];
      Requires = [ "wl-gammarelay-rs.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${chromaPackage}/bin/chroma-daemon";
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.activation.chromaConfigSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/chroma"
      mkdir -p "$config_dir"

      next_config="$(${pkgs.coreutils}/bin/mktemp)"
      cat > "$next_config" << 'CHROMA_DEFAULT_CONFIG'
    ${defaultConfig}CHROMA_DEFAULT_CONFIG
      if [ ! -f "$config_dir/config.dotos" ] \
        || grep -Eq 'ApplyCommand|ApplyTargets|Legacy|\.ya?ml|GhosttyConfigSources' "$config_dir/config.dotos" \
        || ! grep -q 'GhosttyConfigTemplates' "$config_dir/config.dotos" \
        || ! grep -q 'PiThemeControl' "$config_dir/config.dotos" \
        || ! ${pkgs.diffutils}/bin/cmp -s "$next_config" "$config_dir/config.dotos"; then
        ${pkgs.coreutils}/bin/cp "$next_config" "$config_dir/config.dotos"
      fi
      ${pkgs.coreutils}/bin/rm -f "$next_config"
  '';
}
