{
  config,
  inputs,
  lib,
  pkgs,
  horizon,
  hexis,
  ...
}:
let
  profileUser = ((horizon.users or { }).${config.home.username} or { });
  primaryWorkspace = "${config.home.homeDirectory}/primary";
  primaryWorkspacePointer = lib.replaceStrings [ "~" "/" ] [ "~0" "~1" ] primaryWorkspace;
  mediumEnabled = profileUser.size.medium or false;
  edgeEnabled = ((horizon.node.behavesAs or { }).edge or false);
  # Desktop selection is generic projected Edge ownership plus cumulative user
  # size. Individual desktop derivations declare their own availability; this
  # module has no architecture, node-service, or node-identity gate.
  desktopEnabled = edgeEnabled && mediumEnabled;
  codexCliPackage = config.criomos.corePackages.codex;
  codexTui = pkgs.callPackage ../../../../owned-agents/codex/tui.nix { inherit codexCliPackage; };
  claudeCodePackage = config.criomos.corePackages.claude;
  claudeDesktopPackage = pkgs.callPackage ../../../../owned-agents/claude-desktop {
    inherit claudeCodePackage;
  };
  chatgpt = pkgs.callPackage ../../../../owned-agents/chatgpt {
    commandLineArgs = "--ozone-platform=wayland";
  };
  # Codex remains the shared terminal, Remote Control, Agent Intercom, and
  # editor package. ChatGPT Desktop carries its vendor Core independently.
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom {
    inherit inputs codexCliPackage claudeCodePackage;
    codexRawCommand = "${codexCliPackage}/bin/codex";
  };
  # Agent Intercom owns its operational entry points (`coi`, `cci`, MCP
  # servers, and fleet tools), but normal shell commands must remain the
  # pinned upstream CLIs. In an Edge medium profile the Desktop module also
  # supplies `codex`. The producer never exports normal command names; this
  # runtime view hides only explicit raw recovery commands from the user union.
  agentIntercomRuntime = pkgs.symlinkJoin {
    name = "agent-intercom-runtime";
    paths = [ agentIntercom ];
    postBuild = ''
      rm \
        "$out/bin/codex-raw" \
        "$out/bin/claude-raw"
    '';
  };
in
lib.mkMerge [
  {
    # The Codex TUI launcher keeps its caller's working directory when it
    # attaches to the shared app-server. Keep Intercom-specific operational
    # entry points available without letting their aliases shadow ordinary
    # commands. These wrappers and their local integration do not require a
    # node-service gate.
    home.packages = [
      agentIntercomRuntime
      claudeCodePackage
      codexTui
    ];

    home.file = {
      ".pi/agent/packages/agent-intercom-pi" = {
        source = "${agentIntercom}/share/agent-intercom/pi";
        force = true;
      };
      ".pi/agent/packages/agent-intercom-orchestrator" = {
        source = "${agentIntercom}/share/agent-intercom/orchestrator";
        force = true;
      };
      ".pi-testing/agent/packages/agent-intercom-pi" = {
        source = "${agentIntercom}/share/agent-intercom/pi";
        force = true;
      };
      ".pi-testing/agent/packages/agent-intercom-orchestrator" = {
        source = "${agentIntercom}/share/agent-intercom/orchestrator";
        force = true;
      };
    };

    home.activation.mergeAgentIntercomCodexMcp = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.codex/config.toml";
      declared = {
        mcp_servers.agent-intercom = {
          command = "${agentIntercom}/bin/codex-intercom-mcp";
        };
      };
      modes."/mcp_servers/agent-intercom" = "always";
    };

    # Hexis v1 walks declared object leaves. A legacy Claude project entry
    # recorded as a scalar therefore blocks its leaf-only trust write: it is
    # an intermediate path segment, not an object. Canonicalize only that
    # one legacy entry before Hexis owns the trust leaf; existing project
    # objects and all unrelated Claude state remain untouched.
    home.activation.canonicalizeClaudeWorkspaceTrust =
      lib.hm.dag.entryBefore [ "mergeAgentIntercomClaudeMcp" ]
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

    home.activation.mergeAgentIntercomClaudeMcp = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.claude.json";
      declared = {
        mcpServers.agent-intercom = {
          command = "${agentIntercom}/bin/claude-intercom-mcp";
        };
        projects.${primaryWorkspace}.hasTrustDialogAccepted = true;
      };
      modes = {
        "/mcpServers/agent-intercom" = "always";
        "/projects/${primaryWorkspacePointer}/hasTrustDialogAccepted" = "always";
      };
    };

    home.activation.mergeAgentIntercomOpenCodeServerPlugin = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.config/opencode/opencode.json";
      declared = {
        plugin = [ "${agentIntercom}/share/agent-intercom/opencode/dist/plugin.mjs" ];
      };
      modes."/plugin" = "always";
    };

    home.activation.mergeAgentIntercomOpenCodeTuiPlugin = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.config/opencode/tui.json";
      declared = {
        plugin = [ "${agentIntercom}/share/agent-intercom/opencode/dist/tui.mjs" ];
      };
      modes."/plugin" = "always";
    };
  }
  (lib.mkIf (profileUser.size.min or false) {
    # Codex's app-server is the single owner of every normal terminal TUI
    # session.  Its default Unix socket is local to the user, while remote
    # control reaches the phone through Codex's authenticated relay.
    home.packages = [ codexTui ];

    systemd.user.services.codex-remote-control = {
      Unit.Description = "Codex Remote Control app-server";
      Service = {
        WorkingDirectory = primaryWorkspace;
        ExecStart = "${codexCliPackage}/bin/codex app-server --remote-control --listen unix://";
        UMask = "0077";
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

    # The package owns the Claude desktop entry.  Link that exact entry into
    # the active XDG applications directory so the `claude://` callback
    # is discoverable by the desktop MIME database.  The shared Home desktop
    # database activation hook refreshes its cache after link generation.
    xdg.dataFile."applications/claude-desktop.desktop".source =
      "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/claude" = "claude-desktop.desktop";

    # The official Linux ChatGPT package owns this entry.  Keep the entry in
    # the active XDG applications directory and use its executable wrapper.
    xdg.dataFile."applications/chatgpt.desktop".source =
      "${chatgpt}/share/applications/chatgpt.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = "chatgpt.desktop";
  })
]
