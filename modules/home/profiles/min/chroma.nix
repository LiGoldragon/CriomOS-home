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
      dconfMode = if mode == "dark" then "prefer-dark" else "prefer-light";
      gtkTheme = if mode == "dark" then "adw-gtk3-dark" else "adw-gtk3";
      iconTheme = if mode == "dark" then "Papirus-Dark" else "Papirus-Light";
      emacsTheme = if mode == "dark" then "ignis-dark" else "ignis-light";
      fzfColors = mkFzfColors c;
    in
    pkgs.writeShellScript "chroma-apply-${mode}" ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/chroma"
      mkdir -p "$state_dir"

      # Persist first so newly spawned shells see the requested mode
      # immediately, even while slower GUI clients are still catching up.
      echo "${mode}" > "$state_dir/current-mode"
      ${pkgs.coreutils}/bin/date +%s%N > "$state_dir/wezterm-reload"
      echo "export FZF_DEFAULT_OPTS=\"\$FZF_DEFAULT_OPTS ${fzfColors}\"" \
        > "$state_dir/fzf-theme.sh"

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

      # Do not broadcast OSC sequences into /dev/pts. A theme switch
      # must not write into unrelated live TUI panes, and one stalled
      # PTY can block the whole Chroma request. New shells apply
      # terminal colours from current-mode in base.nix.

      # Emacs (any running emacsclient-reachable daemon).
      ${pkgs.coreutils}/bin/timeout 2s ${pkgs.emacs-pgtk}/bin/emacsclient --eval "(progn (add-to-list 'custom-theme-load-path \"$HOME/.config/emacs-ignis-themes\") (mapc #'disable-theme custom-enabled-themes) (load-theme '${emacsTheme} t))" 2>/dev/null || true
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

  profileApplyCommand = "${config.home.homeDirectory}/.nix-profile/bin/chroma-apply-theme";

  # Default config.nota. Chroma reads ApplyCommand from here today;
  # schedule execution is still staged behind the daemon scheduler.
  # Can be edited freely; home-manager only writes it on activation if
  # the file is missing.
  defaultConfig = ''
    (Config
      (Theme
        (ApplyCommand "${profileApplyCommand}")
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
    elif grep -q '^[[:space:]]*(ApplyCommand "/nix/store/.*-chroma-apply-theme/bin/chroma-apply-theme")' "$config_dir/config.nota"; then
      ${pkgs.gnused}/bin/sed -i \
        's|^[[:space:]]*(ApplyCommand "/nix/store/.*-chroma-apply-theme/bin/chroma-apply-theme")|        (ApplyCommand "${profileApplyCommand}")|' \
        "$config_dir/config.nota"
    fi
  '';
}
