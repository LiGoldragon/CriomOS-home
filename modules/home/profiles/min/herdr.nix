{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  herdrPackage = pkgs.callPackage ../../../../packages/herdr { inherit inputs; };
  stableCodexClientPackage = pkgs.writeShellApplication {
    name = "codex-stable-flow-client";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.codex"}
      exec ${config.criomos.corePackages.codex}/bin/codex "$@"
    '';
  };
  legacyHerdrConfig = pkgs.writeText "herdr-legacy-config.toml" ''
    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  predecessorManagedHerdrConfig = pkgs.writeText "herdr-predecessor-managed-config.toml" ''
    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  herdrConfig = pkgs.writeText "herdr-config.toml" ''
    [agents]
    codex_executables = [
      "${stableCodexClientPackage}/bin/codex-stable-flow-client",
      "${config.criomosHome.codexNext.clientPackage}/bin/codex-next-flow-client",
    ]

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
  options.criomosHome.herdr = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = herdrPackage;
      description = "Pinned Herdr package with the CriomOS exact Codex executable boundary.";
    };
    stableCodexClientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = stableCodexClientPackage;
      description = "Immutable Flow client wrapper that sets only stable CODEX_HOME and forwards argv unchanged.";
    };
  };

  config = {
    xdg.configFile."herdr/config.toml".source = herdrConfig;

  # The first managed generation replaces only the observed unmanaged file.
  # The managed target deliberately adds CriomOS theme switching afterwards.
    home.activation.adoptHerdrConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    herdr_config="$HOME/.config/herdr/config.toml"
    herdr_backup_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/criomos/herdr-adoption"
    herdr_backup="$herdr_backup_directory/config.toml.pre-home-manager"
    herdr_checksum="$herdr_backup.sha256"

    verify_legacy_herdr_backup() {
      mkdir -p "$herdr_backup_directory"
      if [ -e "$herdr_backup" ] || [ -L "$herdr_backup" ]; then
        if [ ! -f "$herdr_backup" ] || [ -L "$herdr_backup" ] || ! cmp -s "$herdr_backup" "${legacyHerdrConfig}"; then
          echo "Refusing Herdr adoption: existing backup differs from the observed legacy configuration" >&2
          exit 1
        fi
      else
        cp -- "$herdr_config" "$herdr_backup"
      fi

      herdr_actual_checksum="$(sha256sum "$herdr_backup")"
      if [ -e "$herdr_checksum" ] || [ -L "$herdr_checksum" ]; then
        if [ ! -f "$herdr_checksum" ] || [ -L "$herdr_checksum" ] \
          || ! printf '%s\n' "$herdr_actual_checksum" | cmp -s - "$herdr_checksum"; then
          echo "Refusing Herdr adoption: existing backup checksum does not verify" >&2
          exit 1
        fi
      else
        (umask 077; printf '%s\n' "$herdr_actual_checksum" > "$herdr_checksum")
      fi
    }

    if [ -L "$herdr_config" ]; then
      if [ "$(readlink -f "$herdr_config")" = "${herdrConfig}" ]; then
        :
      elif [ -f "$herdr_config" ] \
        && [[ "$(readlink "$herdr_config")" == /nix/store/*-home-manager-files/.config/herdr/config.toml ]]; then
        # A prior Home Manager generation linked the recorded themed legacy
        # configuration. It is safe to replace only after it and its original
        # pre-Home-Manager backup both verify.
        if ! cmp -s "$herdr_config" "${predecessorManagedHerdrConfig}"; then
          echo "Refusing Herdr adoption: $herdr_config does not match the recorded predecessor configuration" >&2
          exit 1
        fi
        verify_legacy_herdr_backup
        rm -- "$herdr_config"
      else
        echo "Refusing Herdr adoption: $herdr_config is an unmanaged symlink" >&2
        exit 1
      fi
    else
      if [ ! -f "$herdr_config" ]; then
        echo "Refusing Herdr adoption: $herdr_config is missing or is not a regular file" >&2
        exit 1
      fi

      if ! cmp -s "$herdr_config" "${legacyHerdrConfig}"; then
        echo "Refusing Herdr adoption: $herdr_config does not match the observed legacy configuration" >&2
        exit 1
      fi
      verify_legacy_herdr_backup
      rm -- "$herdr_config"
    fi
    '';
  };
}
