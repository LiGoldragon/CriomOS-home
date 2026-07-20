{
  config,
  lib,
  pkgs,
  inputs,
  horizon,
  user,
  hexis,
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

  hasService = node: role: builtins.any (service: serviceName service == role) (node.services or [ ]);

  clusterNodes = [ horizon.node ] ++ lib.attrValues (horizon.exNodes or { });
  gatewayNodes = builtins.filter (node: hasService node "AgentIntercomGateway") clusterNodes;
  peerNodes = builtins.filter (node: hasService node "AgentIntercomPeer") clusterNodes;
  isGateway = hasService horizon.node "AgentIntercomGateway";
  isPeer = hasService horizon.node "AgentIntercomPeer";
  adaptersEnabled = user.size.min;
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom { inherit inputs; };
  codexCliPackage = inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;

  mkRemoteTunnel =
    peer:
    pkgs.writeShellApplication {
      name = "agent-intercom-remote-tunnel-${peer.name}";
      runtimeInputs = [
        agentIntercom
        pkgs.openssh
      ];
      text = ''
        export AGENT_INTERCOM_REMOTE_SSH="${user.name}@${peer.criomeDomainName}"
        export AGENT_INTERCOM_REMOTE_SOCKET="$HOME/.pi/agent/intercom/broker.sock"
        export AGENT_INTERCOM_REMOTE_HEALTH="/run/current-system/sw/bin/agent-intercom-access health"
        exec ${agentIntercom}/share/agent-intercom/secure-remote-tunnel.sh
      '';
    };

  remoteTunnels = builtins.listToAttrs (
    map (peer: {
      name = "agent-intercom-remote-${peer.name}";
      value = {
        Unit = {
          Description = "Authenticated Agent Intercom gateway tunnel to ${peer.criomeDomainName}";
          After = [ "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          EnvironmentFile = "-%h/.config/agent-intercom/remote-tunnel.env";
          ExecStart = "${mkRemoteTunnel peer}/bin/agent-intercom-remote-tunnel-${peer.name}";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    }) peerNodes
  );
in
lib.mkIf adaptersEnabled {
  assertions = [
    {
      assertion = !isGateway || gatewayNodes == [ horizon.node ];
      message = "Agent Intercom gateway selection must resolve to the current projected gateway node";
    }
    {
      assertion = !isPeer || builtins.length gatewayNodes == 1;
      message = "Agent Intercom peers require exactly one projected gateway";
    }
  ];

  home.packages = [ agentIntercom ] ++ lib.optionals isGateway [ pkgs.ydotool ];

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

  home.sessionVariables = lib.optionalAttrs isPeer {
    # The enrollment command writes this owner-only runtime file. The path is
    # declarative; no enrollment or reconnect credential enters the store.
    AGENT_INTERCOM_ACCESS_CREDENTIAL_PATH = "${config.home.homeDirectory}/.local/state/agent-intercom/remote-credential.json";
  };

  systemd.user.services = lib.mkIf isGateway remoteTunnels;

  programs.codexDesktopLinux = lib.mkIf isGateway {
    enable = true;
    cliPackage = codexCliPackage;
    computerUseUi.enable = true;
    remoteMobileControl.enable = true;
    linuxFeatures = [
      "appshots"
      "directory-only-working-tree-watch"
      "frameless-titlebar"
      "mcp-helper-reaper"
      "node-repl-reaper"
      "open-target-discovery"
      "persistent-status-panel"
    ];
    remoteControl = {
      enable = true;
      package = codexCliPackage;
    };
  };
}
