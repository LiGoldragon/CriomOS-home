{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.herdr;
  buildGuard = config.criomosHome.remoteBuildCommandGuard;
  inheritedServicePath = "%h/.local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin";
  herdrPackage = pkgs.callPackage ../../../../packages/herdr { inherit inputs; };
  # Matches the flake input `herdr.url = "github:herdrdev/herdr/v0.8.2"`.
  herdrVersionPin = "0.8.2";
  stableCodexPackage = pkgs.callPackage "${inputs.deployed-codex-source}/owned-agents/codex" {
    manifestFile = "${inputs.deployed-codex-source}/owned-agents/codex/stable-hashes.json";
  };
  stableCodexClientPackage = pkgs.writeShellApplication {
    name = "codex-stable-flow-client";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.codex-next"}
      exec ${stableCodexPackage}/bin/codex "$@"
    '';
  };
  # Keep independent Herdr/module evaluations total; the complete Home
  # profile supplies the candidate package.
  nextCodexClientPackage =
    config.criomosHome.codexNextCandidate.clientPackage or config.criomos.corePackages.codex;
  # Keep the hook byte-for-byte with the pinned Herdr integration that owns
  # its protocol. The Flow next client sets CODEX_HOME=.codex-next, so the
  # ordinary .codex installation is deliberately not reused for this seat.
  codexNextHook = builtins.readFile "${inputs.herdr}/src/integration/assets/codex/herdr-agent-state.sh";
  herdrConfig = pkgs.writeText "herdr-config.toml" ''
    [agents]
    codex_executables = [
      "${stableCodexClientPackage}/bin/codex-stable-flow-client",
      "${nextCodexClientPackage}/bin/codex-next-flow-client",
    ]

    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui.sound]
    enabled = false

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
    versionPin = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = herdrVersionPin;
      description = "Herdr version the flake input pins (herdrdev/herdr/v${herdrVersionPin}); the declared server refuses any other package version.";
    };
    # The Herdr server holds every open pane. Enabling this replaces a
    # server started by hand (a transient `systemd-run herdr server` unit):
    # that handover closes every pane, so it is a window the living opens.
    # The activation guard below refuses while any other server runs.
    server.enable = lib.mkEnableOption "the declared Herdr server user service (herdr-server.service)";
  };

  config = lib.mkMerge [
    (lib.mkIf config.criomosHome.herdr.server.enable {
      assertions = [
        {
          assertion = config.criomosHome.herdr.package.version == herdrVersionPin;
          message = "herdr-server: the Herdr package is ${config.criomosHome.herdr.package.version}, not the pinned ${herdrVersionPin}.";
        }
      ];
      # Observed from the live transient unit: `herdr server`, Type=exec, no
      # restart, control-group kill, in app.slice, from the home directory,
      # with the user manager's environment and no Environment= of its own.
      systemd.user.services.herdr-server = {
        Unit.Description = "Herdr server (terminal workspace for agent panes)";
        Service = {
          Type = "exec";
          Environment = lib.optionals buildGuard.enable [
            "PATH=${buildGuard.directory}:${inheritedServicePath}"
          ];
          ExecStart = "${config.criomosHome.herdr.package}/bin/herdr server";
          WorkingDirectory = "%h";
          Restart = "no";
          KillMode = "control-group";
          Slice = "app.slice";
        };
        Install.WantedBy = [ "default.target" ];
      };
      home.activation.herdrServerHandoverGuard = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        declared_pid="$(${pkgs.systemd}/bin/systemctl --user show -p MainPID --value herdr-server.service 2>/dev/null || echo 0)"
        for pid in $(${pkgs.procps}/bin/pgrep -u "$(id -u)" -x herdr || true); do
          if [ "$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | sed -n 2p)" = server ] && [ "$pid" != "$declared_pid" ]; then
            owner="$(sed -n 's|.*/||p' "/proc/$pid/cgroup" 2>/dev/null | head -n 1)"
            errorEcho "herdr-server: another Herdr server (PID $pid, $owner) holds the panes; stop it in a handover window before activating the declared server"
            exit 1
          fi
        done
      '';
    })
    {
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
  # declaratively: replace only the Herdr next-home hook, retaining every other
  # SessionStart command and all other events.  This hooks file belongs to one
  # CODEX_HOME, so a Herdr hook naming any .codex-next home is ours: the one
  # under $HOME is the declared entry, one under another home is a stale copy
  # carried in by a moved home and would report agent state twice.
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
          and ((.command // "") | type == "string" and contains("/.codex-next/herdr-agent-state.sh"));
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
    }
  ];
}
