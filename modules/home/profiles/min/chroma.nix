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

  chromaPackage = inputs.chroma.packages.${pkgs.stdenv.hostPlatform.system}.default;

  darkPalette = builtins.readFile ../../ignis.nota;
  lightPalette = builtins.readFile ../../ignis-light.nota;

  readNotaPalette =
    path:
    let
      lines = lib.splitString "\n" (builtins.readFile path);
      slot =
        name:
        let
          matches = builtins.filter (match: match != null) (
            map (line: builtins.match ''[[:space:]]*\(${name} "([^"]+)"\).*'' line) lines
          );
        in
        if matches == [ ] then
          throw "missing ${name} in ${toString path}"
        else
          builtins.head (builtins.head matches);
    in
    {
      base00 = slot "Base00";
      base01 = slot "Base01";
      base02 = slot "Base02";
      base03 = slot "Base03";
      base04 = slot "Base04";
      base05 = slot "Base05";
      base06 = slot "Base06";
      base07 = slot "Base07";
      base08 = slot "Base08";
      base09 = slot "Base09";
      base0A = slot "Base0A";
      base0B = slot "Base0B";
      base0C = slot "Base0C";
      base0D = slot "Base0D";
      base0E = slot "Base0E";
      base0F = slot "Base0F";
    };

  dark = readNotaPalette ../../ignis.nota;
  light = readNotaPalette ../../ignis-light.nota;

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
        (Concerns Terminal Desktop Ghostty Emacs)
        (Palettes
    ${darkPalette}
    ${lightPalette})
        (Adapters
          (Dconf "${pkgs.dconf}/bin/dconf")
          (Emacsclient "${pkgs.emacs-pgtk}/bin/emacsclient"))
        (FontPointSize ${toString fontPt})
        (GhosttyConfigTemplates
          (Dark "${ghosttyDarkConfig}")
          (Light "${ghosttyLightConfig}"))
        (Schedule
          (Waypoint (CivilDawn (SignedMinutes 0)) Light)
          (Waypoint (CivilDusk (SignedMinutes 0)) Dark)
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
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/chroma"
      mkdir -p "$config_dir" "$state_dir"

      next_config="$(${pkgs.coreutils}/bin/mktemp)"
      cat > "$next_config" << 'CHROMA_DEFAULT_CONFIG'
    ${defaultConfig}CHROMA_DEFAULT_CONFIG
      if [ ! -f "$config_dir/config.nota" ] \
        || grep -Eq 'ApplyCommand|ApplyTargets|Legacy|\.ya?ml|GhosttyConfigSources' "$config_dir/config.nota" \
        || ! grep -q 'GhosttyConfigTemplates' "$config_dir/config.nota" \
        || ! ${pkgs.diffutils}/bin/cmp -s "$next_config" "$config_dir/config.nota"; then
        ${pkgs.coreutils}/bin/cp "$next_config" "$config_dir/config.nota"
      fi
      ${pkgs.coreutils}/bin/rm -f "$next_config"

    if [ ! -f "$state_dir/current-mode" ]; then
      echo "dark" > "$state_dir/current-mode"
    fi
  '';
}
