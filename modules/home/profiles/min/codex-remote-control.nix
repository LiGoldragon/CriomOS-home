{
  config,
  inputs,
  lib,
  pkgs,
  horizon,
  user,
  hexis,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  buildGuard = config.criomosHome.remoteBuildCommandGuard;
  inheritedServicePath = "%h/.local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin";
  primaryWorkspace = "${config.home.homeDirectory}/primary";
  primaryWorkspacePointer = lib.replaceStrings [ "~" "/" ] [ "~0" "~1" ] primaryWorkspace;
  mediumEnabled = sizeAtLeast "Medium";
  edgeEnabled = ((horizon.node.behavesAs or { }).edge or false);
  desktopEnabled = edgeEnabled && mediumEnabled;
  # The user's key here carrying StableCodex keeps the stable core Codex and its own account data.
  stableCodex = builtins.elem "StableCodex" user.capabilities;
  codexCliPackage = config.criomos.corePackages.codex;
  codexServerPackage = config.criomos.corePackages.codexServer;
  remoteClient = if stableCodex then "${codexCliPackage}/bin/codex" else "${config.criomosHome.codexNext.rawClientPackage}/bin/codex";
  codexStable = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.codex-next"}
      exec ${remoteClient} --remote ${lib.escapeShellArg "unix://${config.home.homeDirectory}/.codex-next/app-server-control/app-server-control.sock"} "$@"
    '';
  };
  codexRemote = pkgs.callPackage ../../../../owned-agents/codex/remote.nix {
    inherit codexCliPackage;
    endpoint = "unix://${config.home.homeDirectory}/.codex-next/app-server-control/app-server-control.sock";
  };
  claudeCodePackage = config.criomos.corePackages.claude;
  claudePermissionRequestHook = pkgs.callPackage ../../../../owned-agents/claude-code/permission-request-hook.nix { };
  claudeDesktopPackage =pkgs.callPackage ../../../../owned-agents/claude-desktop {
    inherit claudeCodePackage;
  };
  chatgpt = pkgs.callPackage ../../../../owned-agents/chatgpt {
    commandLineArgs = "--ozone-platform=wayland";
  };
in
lib.mkMerge [
  {
    home.sessionVariables = lib.mkIf (user.capabilities != [ ]) {
      CLAUDE_CODE_ARTIFACT_AUTO_OPEN = "0";
    };

    home.packages = [
      claudeCodePackage
      codexCliPackage
    ];

    # Bypass still asks a human for the dangerous-removal check.  The
    # PermissionRequest hook denies it with a rewrite message and logs every
    # request to ~/.local/state/claude/permission-requests.jsonl.  Only this
    # hook event is asserted; Herdr's SessionStart hook and other events stay
    # user state.
    home.activation.mergeClaudePermissionDefaults = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.claude/settings.json";
      declared = {
        permissions.defaultMode = "bypassPermissions";
        hooks.PermissionRequest = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "${claudePermissionRequestHook}/bin/claude-permission-request-hook";
              }
            ];
          }
        ];
      } // lib.optionalAttrs (user.capabilities != [ ]) {
        env.CLAUDE_CODE_ARTIFACT_AUTO_OPEN = "0";
      };
      modes = {
        "/permissions/defaultMode" = "always";
        "/hooks/PermissionRequest" = "always";
      } // lib.optionalAttrs (user.capabilities != [ ]) {
        "/env/CLAUDE_CODE_ARTIFACT_AUTO_OPEN" = "always";
      };
    };

    home.activation.canonicalizeClaudeWorkspaceTrust =
      lib.hm.dag.entryBefore [ "mergeClaudeWorkspaceTrust" ]
        ''
          claude_config="$HOME/.claude.json"
          workspace=${lib.escapeShellArg primaryWorkspace}
          if [ -f "$claude_config" ]; then
            if ${pkgs.jq}/bin/jq -e --arg workspace "$workspace" '
              (.projects | type) == "object"
              and .projects[$workspace] != null
              and (.projects[$workspace] | type) != "object"
            ' "$claude_config" >/dev/null; then
              temporary_config="$(${pkgs.coreutils}/bin/mktemp "$claude_config.XXXXXX")"
              ${pkgs.jq}/bin/jq --arg workspace "$workspace" \
                '.projects[$workspace] = { hasTrustDialogAccepted: true }' \
                "$claude_config" > "$temporary_config"
              ${pkgs.coreutils}/bin/chmod --reference="$claude_config" "$temporary_config"
              ${pkgs.coreutils}/bin/mv "$temporary_config" "$claude_config"
            fi
          fi
        '';

    home.activation.mergeClaudeWorkspaceTrust = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.claude.json";
      declared.projects.${primaryWorkspace}.hasTrustDialogAccepted = true;
      modes."/projects/${primaryWorkspacePointer}/hasTrustDialogAccepted" = "always";
    };
  }
  (lib.mkIf (sizeAtLeast "Min") {
    home.packages = [ codexRemote ];

    systemd.user.services.codex-remote-control = {
      # It serves the primary checkout; on a host where this user has none,
      # the unit is skipped rather than failing at its working directory.
      Unit = {
        Description = "Codex Remote Control app-server";
        ConditionPathIsDirectory = primaryWorkspace;
      };
      Service = {
        WorkingDirectory = primaryWorkspace;
        Environment = lib.optionals buildGuard.enable [
          "PATH=${buildGuard.directory}:${inheritedServicePath}"
        ];
        ExecStart = "${codexServerPackage}/bin/codex app-server --remote-control --listen unix://";
        UMask = "0077";
        LimitNOFILE = 524288;
        Restart = "always";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  })
  (lib.mkIf desktopEnabled {
    home.packages = [
      claudeDesktopPackage
      chatgpt
    ];

    xdg.dataFile."applications/claude-desktop.desktop".source =
      "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/claude" = "claude-desktop.desktop";
    xdg.dataFile."applications/chatgpt.desktop".source =
      "${chatgpt}/share/applications/chatgpt.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = "chatgpt.desktop";
  })
]
