{
  inputs,
  lib,
  pkgs,
  homeSystem,
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
  # This guard is evaluated while Home Manager merges imports, before its
  # lazily supplied `pkgs` module argument is available.  The flake supplies
  # its already-resolved target platform as `homeSystem`, leaving package
  # selection below on `pkgs` once option values are forced.
  graphicalSupported = homeSystem == "x86_64-linux";
  sharedAppServerSocket = "unix://\${XDG_RUNTIME_DIR}/codex-intercom-app-server.sock";
  codexCliPackage = inputs.codex-cli.packages.${homeSystem}.default;
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom {
    inherit inputs;
    sharedAppServerSocket =
      if graphicalEnabled && graphicalSupported then sharedAppServerSocket else null;
  };
in
lib.mkMerge (
  [
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
  ++ lib.optional (graphicalEnabled && graphicalSupported) {
    programs.codexDesktopLinux = {
      enable = true;
      cliPackage = codexCliPackage;
      computerUseUi.enable = true;
      remoteMobileControl.enable = true;
      remoteControl = {
        enable = true;
        package = codexCliPackage;
        listen = sharedAppServerSocket;
      };
    };

    systemd.user.services.agent-intercom-codex-bridge = {
      Unit = {
        Description = "Agent Intercom bridge for the Desktop-owned Codex app-server";
        Requires = [ "codex-remote-control.service" ];
        BindsTo = [ "codex-remote-control.service" ];
        PartOf = [ "codex-remote-control.service" ];
        After = [ "codex-remote-control.service" ];
      };
      Service = {
        WorkingDirectory = config.home.homeDirectory;
        ExecStart = lib.escapeShellArgs [
          "${agentIntercom}/bin/coi"
          "--no-tui"
          "--intercom-id"
          "codex-desktop"
          "--intercom-name"
          "Codex Desktop"
        ];
        Restart = "always";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  }
)
