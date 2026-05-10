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
    pkgs.emacs-pgtk
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
        || grep -Eq 'ApplyCommand|ApplyTargets|Legacy|\.ya?ml' "$config_dir/config.nota"; then
        cat > "$config_dir/config.nota" << 'CHROMA_DEFAULT_CONFIG'
    ${defaultConfig}CHROMA_DEFAULT_CONFIG
      fi

      if [ ! -f "$state_dir/current-mode" ]; then
        echo "dark" > "$state_dir/current-mode"
      fi
      ${pkgs.coreutils}/bin/date +%s%N > "$state_dir/wezterm-reload"
  '';
}
