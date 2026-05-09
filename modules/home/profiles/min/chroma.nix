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

  # ─── Palette parsing (shared shape, kept local to this module) ───────
  darkScheme = ../../ignis.yaml;
  lightScheme = ../../ignis-light.yaml;

  parseScheme =
    scheme:
    (lib.importJSON (
      pkgs.runCommand "base16-to-json"
        {
          nativeBuildInputs = [ pkgs.yq-go ];
        }
        ''
          yq -o=json '.' ${scheme} > $out
        ''
    )).palette;

  mkOscSequence =
    c:
    let
      osc = n: color: ''\033]4;${toString n};${color}\007'';
    in
    ''
      ${osc 0 c.base00}${osc 1 c.base08}${osc 2 c.base0B}${osc 3 c.base0A}\
      ${osc 4 c.base0D}${osc 5 c.base0E}${osc 6 c.base0C}${osc 7 c.base05}\
      ${osc 8 c.base03}${osc 9 c.base08}${osc 10 c.base0B}${osc 11 c.base0A}\
      ${osc 12 c.base0D}${osc 13 c.base0E}${osc 14 c.base0C}${osc 15 c.base07}\
      \033]10;${c.base05}\007\033]11;${c.base00}\007\033]12;${c.base05}\007'';

  mkFzfColors =
    c:
    "--color=bg:${c.base00},bg+:${c.base01},fg:${c.base04},fg+:${c.base06}"
    + ",hl:${c.base0D},hl+:${c.base0D},info:${c.base0A},marker:${c.base0C}"
    + ",prompt:${c.base0A},spinner:${c.base0C},pointer:${c.base0C},header:${c.base0D}";

  # ─── Apply script — invoked by chroma-daemon on theme switch ─────────
  mkApplyScript =
    {
      mode,
      scheme,
    }:
    let
      c = parseScheme scheme;
      oscSeq = mkOscSequence c;
      dconfMode = if mode == "dark" then "prefer-dark" else "prefer-light";
      gtkTheme = if mode == "dark" then "adw-gtk3-dark" else "adw-gtk3";
      iconTheme = if mode == "dark" then "Papirus-Dark" else "Papirus-Light";
      emacsTheme = if mode == "dark" then "ignis-dark" else "ignis-light";
      fzfColors = mkFzfColors c;
    in
    pkgs.writeShellScript "chroma-apply-${mode}" ''
      # Portal + dconf (Firefox, Electron, Qt apps).
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'${dconfMode}'"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/gtk-theme "'${gtkTheme}'"
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/icon-theme "'${iconTheme}'"

      # GTK 3 / 4 settings.ini (apps that read the file, not dconf).
      for v in gtk-3.0 gtk-4.0; do
        mkdir -p "$HOME/.config/$v"
        cat > "$HOME/.config/$v/settings.ini" << 'GTKEOF'
      [Settings]
      gtk-theme-name=${gtkTheme}
      gtk-cursor-theme-name=Bibata-Modern-Classic
      gtk-cursor-theme-size=24
      gtk-font-name=DejaVu Sans 12
      gtk-icon-theme-name=${iconTheme}
      GTKEOF
      done

      # Ghostty config (regenerated each switch).
      mkdir -p "$HOME/.config/ghostty"
      cat > "$HOME/.config/ghostty/config" << 'GHOSTTY'
      font-family = IosevkaTerm Nerd Font
      font-size = ${toString fontPt}
      window-decoration = false
      gtk-titlebar = false
      window-theme = ghostty
      background = ${c.base00}
      foreground = ${c.base05}
      GHOSTTY

      # OSC sequences to every live PTY.
      SEQ="${oscSeq}"
      for pty in /dev/pts/[0-9]*; do
        printf "$SEQ" > "$pty" 2>/dev/null || true
      done

      # Emacs (any running emacsclient-reachable daemon).
      ${pkgs.emacs-pgtk}/bin/emacsclient --eval "(progn (add-to-list 'custom-theme-load-path \"$HOME/.config/emacs-ignis-themes\") (mapc #'disable-theme custom-enabled-themes) (load-theme '${emacsTheme} t))" 2>/dev/null || true

      # fzf colours (sourced by new shells).
      mkdir -p "''${XDG_STATE_HOME:-$HOME/.local/state}/chroma"
      echo "export FZF_DEFAULT_OPTS=\"\$FZF_DEFAULT_OPTS ${fzfColors}\"" \
        > "''${XDG_STATE_HOME:-$HOME/.local/state}/chroma/fzf-theme.sh"

      # Persisted current mode (read by zsh init in new shells).
      echo "${mode}" > "''${XDG_STATE_HOME:-$HOME/.local/state}/chroma/current-mode"
    '';

  applyDark = mkApplyScript {
    mode = "dark";
    scheme = darkScheme;
  };
  applyLight = mkApplyScript {
    mode = "light";
    scheme = lightScheme;
  };

  # ─── Dispatcher — invoked by chroma-daemon's ApplyCommand ────────────
  chromaApplyTheme = pkgs.writeShellScriptBin "chroma-apply-theme" ''
    case "''${1:-}" in
      dark)  exec ${applyDark} ;;
      light) exec ${applyLight} ;;
      *)     echo "usage: chroma-apply-theme <dark|light>" >&2; exit 2 ;;
    esac
  '';

  chromaPackage = inputs.chroma.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Default config.nota. Chroma reads ApplyCommand from here today;
  # schedule execution is still staged behind the daemon scheduler.
  # Can be edited freely; home-manager only writes it on activation if
  # the file is missing.
  defaultConfig = ''
    (Config
      (Theme
        (ApplyCommand "${chromaApplyTheme}/bin/chroma-apply-theme")
        (Schedule
          (Waypoint (CivilDawn (SignedMinutes 0)) Light)
          (Waypoint (CivilDusk (SignedMinutes 0)) Dark)))
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
    chromaApplyTheme
    # Backwards-compat wrappers — match the old `theme-dark` / `theme-light`
    # invocations from base.nix; just thin clients to the chroma daemon.
    (pkgs.writeShellScriptBin "theme-dark" ''
      exec ${chromaPackage}/bin/chroma '(SetTheme Dark)'
    '')
    (pkgs.writeShellScriptBin "theme-light" ''
      exec ${chromaPackage}/bin/chroma '(SetTheme Light)'
    '')
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
      # Chroma defaults to $XDG_RUNTIME_DIR/chroma.sock. Keep the
      # service and CLI on the same per-user runtime socket; do not
      # depend on a freshly-granted supplementary group in a live
      # graphical session.
      Restart = "on-failure";
      RestartSec = "2s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Drop a default config.nota on first activation. The daemon reads
  # ApplyCommand from this file, while scheduled fires are still future
  # work.
  home.activation.chromaConfigSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/chroma"
    if [ ! -f "$config_dir/config.nota" ]; then
      mkdir -p "$config_dir"
      cat > "$config_dir/config.nota" << 'CHROMA_DEFAULT_CONFIG'
    ${defaultConfig}CHROMA_DEFAULT_CONFIG
    fi
  '';
}
