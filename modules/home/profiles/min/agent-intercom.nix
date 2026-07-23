{
  inputs,
  lib,
  pkgs,
  horizon,
  hexis,
  config,
  ...
}:
let
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
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom { inherit inputs; };

  # The pinned Desktop module wraps a configured cliPackage into
  # CODEX_CLI_PATH and can independently own `codex app-server` through its
  # remote-control service. The pinned `coi` source instead owns a raw-Codex
  # app-server and remote TUI for one Intercom session. It is therefore not a
  # drop-in Desktop CLI and has no supported Desktop attachment surface.
  desktopHardGateMessage = "Agent Intercom Desktop activation is blocked: pinned ilysenko/codex-desktop-linux wraps cliPackage as CODEX_CLI_PATH and its remote-control service invokes codex app-server, while pinned coi owns a separate raw-Codex app-server and remote TUI. CODEX_CLI_PATH must remain a drop-in raw Codex CLI; setting it to coi would misinterpret Desktop app-server arguments or create competing ownership. No supported attachment exists, so keep programs.codexDesktopLinux.enable = false. Computer Use and Mobile Control stay inactive with Desktop; ordinary MCP is not a wakeable substitute.";
in
lib.mkMerge [
  {
    assertions = [
      {
        assertion = !graphicalEnabled || localEnabled;
        message = "graphical Agent Intercom requires local Agent Intercom";
      }
      {
        assertion = !config.programs.codexDesktopLinux.enable;
        message = desktopHardGateMessage;
      }
    ];
  }
  (lib.mkIf localEnabled {
    # `codex` and `claude` in this package are the normal, wakeable entry
    # points. `codex-raw` and `claude-raw` remain explicit recovery/debug
    # executables; no regular launcher resolves directly to the upstream CLI.
    home.packages = [ agentIntercom ];

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
]
