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
    c:
    lib.concatStringsSep "\n" [
      "palette = 0=${c.base00}"
      "palette = 1=${c.base08}"
      "palette = 2=${c.base0B}"
      "palette = 3=${c.base0A}"
      "palette = 4=${c.base0D}"
      "palette = 5=${c.base0E}"
      "palette = 6=${c.base0C}"
      "palette = 7=${c.base05}"
      "palette = 8=${c.base03}"
      "palette = 9=${c.base08}"
      "palette = 10=${c.base0B}"
      "palette = 11=${c.base0A}"
      "palette = 12=${c.base0D}"
      "palette = 13=${c.base0E}"
      "palette = 14=${c.base0C}"
      "palette = 15=${c.base07}"
    ];

  mkGhosttyConfig =
    {
      name,
      colors,
    }:
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
      ${mkGhosttyPaletteLines colors}
    '';

  ghosttyDarkConfig = mkGhosttyConfig {
    name = "dark";
    colors = dark;
  };
  ghosttyLightConfig = mkGhosttyConfig {
    name = "light";
    colors = light;
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

      if [ ! -f "$config_dir/config.nota" ] \
        || grep -Eq 'ApplyCommand|ApplyTargets|Legacy|\.ya?ml|GhosttyConfigSources' "$config_dir/config.nota" \
        || ! grep -q 'GhosttyConfigTemplates' "$config_dir/config.nota"; then
        cat > "$config_dir/config.nota" << 'CHROMA_DEFAULT_CONFIG'
    ${defaultConfig}CHROMA_DEFAULT_CONFIG
      fi

    if [ ! -f "$state_dir/current-mode" ]; then
      echo "dark" > "$state_dir/current-mode"
    fi
  '';
}
