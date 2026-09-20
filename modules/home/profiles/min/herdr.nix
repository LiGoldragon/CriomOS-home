{ lib, pkgs, ... }:
let
  herdrConfig = pkgs.writeText "herdr-config.toml" ''
    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
in
{
  xdg.configFile."herdr/config.toml".source = herdrConfig;

  # The first managed generation may replace only the captured configuration
  # below. Any other file shape, including a dangling or foreign symlink,
  # remains a deployment-time review stop.
  home.activation.adoptHerdrConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    herdr_config="$HOME/.config/herdr/config.toml"
    herdr_backup_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/criomos/herdr-adoption"
    herdr_backup="$herdr_backup_directory/config.toml.pre-home-manager"
    herdr_checksum="$herdr_backup.sha256"

    if [ -L "$herdr_config" ]; then
      if [ "$(readlink -f "$herdr_config")" = "${herdrConfig}" ]; then
        :
      else
        echo "Refusing Herdr adoption: $herdr_config is an unmanaged symlink" >&2
        exit 1
      fi
    else
      if [ ! -f "$herdr_config" ]; then
        echo "Refusing Herdr adoption: $herdr_config is missing or is not a regular file" >&2
        exit 1
      fi

      if ! cmp -s "$herdr_config" "${herdrConfig}"; then
        echo "Refusing Herdr adoption: $herdr_config does not match the declared configuration" >&2
        exit 1
      fi

      mkdir -p "$herdr_backup_directory"
      if [ -e "$herdr_backup" ]; then
        if ! cmp -s "$herdr_backup" "${herdrConfig}"; then
          echo "Refusing Herdr adoption: existing backup differs from the declared configuration" >&2
          exit 1
        fi
      else
        cp -- "$herdr_config" "$herdr_backup"
      fi

      if [ -e "$herdr_checksum" ]; then
        if ! sha256sum --check --status "$herdr_checksum"; then
          echo "Refusing Herdr adoption: existing backup checksum does not verify" >&2
          exit 1
        fi
      else
        sha256sum "$herdr_backup" > "$herdr_checksum"
      fi

      rm -- "$herdr_config"
    fi
  '';
}
