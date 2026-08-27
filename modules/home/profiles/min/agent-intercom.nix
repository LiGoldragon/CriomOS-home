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
  serviceName =
    service:
    if builtins.isString service then
      service
    else if builtins.isAttrs service then
      let
        names = builtins.attrNames service;
      in
      if builtins.length names == 1 then builtins.head names else null
    else
      null;

  hasCapability =
    name: builtins.any (service: serviceName service == name) (horizon.node.services or [ ]);

  localEnabled = hasCapability "AgentIntercomLocal";
  graphicalEnabled = hasCapability "AgentIntercomGraphical";
  mediumEnabled = profileUser.size.medium or false;
  desktopEnabled = graphicalEnabled && mediumEnabled;
  # Only the projected capability, which is an early special argument, decides
  # whether the Desktop option block exists below.  The package-set platform
  # guard remains a later assertion: forcing it while constructing the module
  # list recurses through Home Manager's `_module.args.pkgs`.
  homeSystem = pkgs.stdenv.hostPlatform.system;
  graphicalSupported = homeSystem == "x86_64-linux";
  codexCliPackage = config.criomos.corePackages.codex;
  codexTui = pkgs.callPackage ../../../../owned-agents/codex/tui.nix { inherit codexCliPackage; };
  codexDesktopGate = pkgs.callPackage ../../../../owned-agents/codex/desktop-gate.nix {
    inherit codexCliPackage;
  };
  claudeCodePackage = config.criomos.corePackages.claude;
  claudeDesktopPackage = pkgs.callPackage ../../../../owned-agents/claude-desktop {
    inherit claudeCodePackage;
  };
  chatgptWithDesktopGate = pkgs.callPackage ../../../../owned-agents/chatgpt {
    codexPackage = codexCliPackage;
    inherit codexDesktopGate;
    commandLineArgs = "--ozone-platform=wayland";
  };
  chatgptWithLocalDaemon = pkgs.symlinkJoin {
    name = "chatgpt-with-local-codex-daemon";
    paths = [ chatgptWithDesktopGate ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/chatgpt"
      makeWrapper ${chatgptWithDesktopGate}/bin/chatgpt "$out/bin/chatgpt" \
        --set CODEX_APP_SERVER_USE_LOCAL_DAEMON 1 \
        --unset CODEX_CLI_PATH \
        --unset CODEX_APP_SERVER_FORCE_CLI \
        --unset CODEX_APP_SERVER_CLI_COMMAND
    '';
  };
  # The shared package is the sole Codex derivation for the terminal,
  # Desktop, Agent Intercom, and editor paths.
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom {
    inherit inputs codexCliPackage claudeCodePackage;
    codexRawCommand = "${codexCliPackage}/bin/codex";
  };
  # Agent Intercom owns its operational entry points (`coi`, `cci`, MCP
  # servers, and fleet tools), but normal shell commands must remain the
  # pinned upstream CLIs.  In a graphical profile the Desktop module also
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
    assertions = [
      {
        assertion = !graphicalEnabled || localEnabled;
        message = "graphical Agent Intercom requires local Agent Intercom";
      }
      {
        assertion = !graphicalEnabled || graphicalSupported;
        message = "graphical Agent Intercom requires x86_64-linux Desktop support";
      }
    ];
  }
  (lib.mkIf localEnabled {
    # The Codex TUI launcher keeps its caller's working directory when it
    # attaches to the shared app-server. Keep Intercom-specific operational
    # entry points without letting their aliases shadow ordinary commands.
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

    home.activation.mergeAgentIntercomClaudeMcp = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs hexis;
      file = "$HOME/.claude.json";
      declared = {
        mcpServers.agent-intercom = {
          command = "${agentIntercom}/bin/claude-intercom-mcp";
        };
      };
      modes."/mcpServers/agent-intercom" = "always";
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
  })
  (lib.mkIf (profileUser.size.min or false) {
    # Codex's app-server is the single owner of every normal terminal TUI
    # session.  Its default Unix socket is local to the user, while remote
    # control reaches the phone through Codex's authenticated relay.
    home.packages = [ codexTui ];

    systemd.user.services.codex-remote-control = {
      Unit.Description = "Codex Remote Control app-server";
      Service = {
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
      chatgptWithLocalDaemon
    ];

    # The package owns the Claude desktop entry.  Link that exact entry into
    # the active XDG applications directory so the `claude://` callback
    # is discoverable by the desktop MIME database.  The shared Home desktop
    # database activation hook refreshes its cache after link generation.
    xdg.dataFile."applications/claude-desktop.desktop".source =
      "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/claude" = "claude-desktop.desktop";

    # The official Linux ChatGPT package owns this entry.  Keep the entry in
    # the active XDG applications directory and use its executable wrapper so
    # the GUI and terminal both use the sole shared Codex derivation.
    xdg.dataFile."applications/chatgpt.desktop".source =
      "${chatgptWithLocalDaemon}/share/applications/chatgpt.desktop";
    xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = "chatgpt.desktop";
  })
]
