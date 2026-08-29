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

  mkChromaPalette = colors: ''
    {
      ${colors.base00}
      ${colors.base01}
      ${colors.base02}
      ${colors.base03}
      ${colors.base04}
      ${colors.base05}
      ${colors.base06}
      ${colors.base07}
      ${colors.base08}
      ${colors.base09}
      ${colors.base0A}
      ${colors.base0B}
      ${colors.base0C}
      ${colors.base0D}
      ${colors.base0E}
      ${colors.base0F}
    }
  '';

  darkPalette = mkChromaPalette dark;
  lightPalette = mkChromaPalette light;

  solarOffsetMinutes =
    timing:
    if timing == "ExtremelyEarly" then
      -120
    else if timing == "VeryEarly" then
      -60
    else if timing == "Early" then
      -30
    else if timing == "OnTime" then
      0
    else if timing == "Late" then
      30
    else if timing == "VeryLate" then
      60
    else if timing == "ExtremelyLate" then
      120
    else
      throw "Chroma's legacy solar timing ${timing} has no Datomic offset.";

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
    {
      {
        [Terminal Desktop Ghostty Pi]
        {
          ${darkPalette}
          ${lightPalette}
        }
        Some.${pkgs.dconf}/bin/dconf
        Some.${toString fontPt}
        Some.{${ghosttyDarkConfig} ${ghosttyLightConfig}}
        Some.{RuntimeRelative.chroma/pi-live-theme.d Some.100 Some.100}
        Scheduled.{
          [
            {Sunrise.${toString (solarOffsetMinutes lightThemeSwitchTiming)} Light}
            {Sunset.${toString (solarOffsetMinutes darkThemeSwitchTiming)} Dark}
          ]
          Dark
        }
      }
      {
        Scheduled.{
          [
            {CivilDawn.-30 Cold Minutes.30}
            {CivilDusk.-60 Warmest Minutes.60}
          ]
          Neutral
        }
      }
      {Manual.Bright}
    }
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
      if [ ! -f "$config_dir/config.datom" ] \
        || ! ${pkgs.diffutils}/bin/cmp -s "$next_config" "$config_dir/config.datom"; then
        ${pkgs.coreutils}/bin/cp "$next_config" "$config_dir/config.datom"
      fi
      ${pkgs.coreutils}/bin/rm -f "$config_dir/config.dotos"
      ${pkgs.coreutils}/bin/rm -f "$next_config"
  '';
}
