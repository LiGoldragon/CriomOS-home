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
  primaryWorkspace = "${config.home.homeDirectory}/primary";
  primaryWorkspacePointer = lib.replaceStrings [ "~" "/" ] [ "~0" "~1" ] primaryWorkspace;
  mediumEnabled = sizeAtLeast "Medium";
  edgeEnabled = ((horizon.node.behavesAs or { }).edge or false);
  desktopEnabled = edgeEnabled && mediumEnabled;
  occupied = config.home.homeDirectory == "/home/li";
  codexCliPackage = config.criomos.corePackages.codex;
  # This server has an unregistered client attached.  It is frozen until that
  # client has moved; do not replace its executable with the current package.
  # The literal is the executable in the preserved live-unit receipt.
  occupiedCodex = "/nix/store/wdj0sc69r4n9is1idfb32vcx5739ijkh-codex-0.153.4/bin/codex";
  occupiedNextCodex = "/nix/store/zbznvqk2746igprz4753clizppww5551-codex-next-0.158.0-alpha.9/bin/codex";
  codexStable = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.codex-next"}
      exec ${occupiedNextCodex} --remote ${lib.escapeShellArg "unix://${config.home.homeDirectory}/.codex-next/app-server-control/app-server-control.sock"} "$@"
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
    home.packages = [
      claudeCodePackage
      (if occupied then codexStable else codexCliPackage)
    ];

    # Bypass still asks a human for the dangerous-removal check.  The
    # PermissionRequest hook denies it with a rewrite message and logs every
    # request to ~/.local/state/claude/permission-requests.jsonl.  Only this
    # event key is asserted; Herdr's SessionStart hook and other events stay
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
      };
      modes = {
        "/permissions/defaultMode" = "always";
        "/hooks/PermissionRequest" = "always";
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
      Unit.Description = "Codex Remote Control app-server";
      Service = {
        WorkingDirectory = primaryWorkspace;
        # Keep this definition byte-for-byte compatible with the occupied
        # service.  A later role transition may replace it only after its
        # unregistered client is gone.
        ExecStart = "${if occupied then occupiedCodex else "${codexCliPackage}/bin/codex"} app-server --remote-control --listen unix://";
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
