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
  # Keep the hook byte-for-byte with the pinned Herdr integration that owns
  # its protocol. The Flow next client sets CODEX_HOME=.codex-next, so the
  # ordinary .codex installation is deliberately not reused for this seat.
  codexNextHook = builtins.readFile "${inputs.herdr}/src/integration/assets/codex/herdr-agent-state.sh";
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

  home.file.".codex-next/herdr-agent-state.sh" = {
    text = codexNextHook;
    executable = true;
  };

  # Hexis owns only the feature which makes Codex consume hooks; every other
  # key in this separate next-client configuration remains user state.
  home.activation.mergeCodexNextHerdrFeature = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs;
    hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
    file = "$HOME/.codex-next/config.toml";
    declared.features.hooks = true;
    modes."/features/hooks" = "always";
  };

  # Herdr's supported installer preserves foreign hook groups.  Do the same
  # declaratively: replace only this next-home hook, retaining every other
  # SessionStart command and all other events.
  home.activation.mergeCodexNextHerdrSessionHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    hooks_path="$HOME/.codex-next/hooks.json"
    hook_path="$HOME/.codex-next/herdr-agent-state.sh"
    mkdir -p "$HOME/.codex-next"
    if [ -e "$hooks_path" ] && [ ! -f "$hooks_path" ]; then
      echo "Refusing Herdr Codex hook merge: $hooks_path is not a regular file" >&2
      exit 1
    fi
    temporary_hooks="$(${pkgs.coreutils}/bin/mktemp "$hooks_path.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temporary_hooks"' EXIT
    if [ -e "$hooks_path" ]; then
      ${pkgs.jq}/bin/jq --arg hook "$hook_path" '
        def ours:
          (.type == "command")
          and ((.command // "") | type == "string" and contains($hook));
        if type != "object" then error("Codex hooks root must be an object") else . end
        | .hooks = (.hooks // {})
        | if (.hooks | type) != "object" then error("Codex hooks must be an object") else . end
        | .hooks.SessionStart = (
            (.hooks.SessionStart // [])
            | if type != "array" then error("Codex SessionStart hooks must be an array") else . end
            | [ .[]
                | if (.hooks | type?) == "array" then
                    .hooks |= map(select(ours | not))
                  else . end
                | select((.hooks | type?) != "array" or (.hooks | length) > 0)
              ]
            + [{ hooks: [{ type: "command", command: ("bash " + ($hook | @sh) + " session"), timeout: 10 }] }]
          )
      ' "$hooks_path" > "$temporary_hooks"
    else
      ${pkgs.jq}/bin/jq -n --arg hook "$hook_path" \
        '{ hooks: { SessionStart: [{ hooks: [{ type: "command", command: ("bash " + ($hook | @sh) + " session"), timeout: 10 }] }] } }' \
        > "$temporary_hooks"
    fi
    ${pkgs.coreutils}/bin/mv "$temporary_hooks" "$hooks_path"
    trap - EXIT
  '';
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
        # A prior Home Manager generation linked the recorded themed
        # configuration. That generation followed the first adoption, which
        # recorded the pre-Home-Manager backup. It is safe to replace only after
        # the link and that existing backup both verify; the linked file is
        # Home Manager's own output and is never recorded as the backup.
        if ! cmp -s "$herdr_config" "${predecessorManagedHerdrConfig}"; then
          echo "Refusing Herdr adoption: $herdr_config does not match the recorded predecessor configuration" >&2
          exit 1
        fi
        if [ ! -f "$herdr_backup" ] || [ -L "$herdr_backup" ]; then
          echo "Refusing Herdr adoption: predecessor link has no recorded pre-Home-Manager backup at $herdr_backup" >&2
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
