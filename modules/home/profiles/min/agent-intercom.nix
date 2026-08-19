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
  # Only the projected capability, which is an early special argument, decides
  # whether the Desktop option block exists below.  The package-set platform
  # guard remains a later assertion: forcing it while constructing the module
  # list recurses through Home Manager's `_module.args.pkgs`.
  homeSystem = pkgs.stdenv.hostPlatform.system;
  graphicalSupported = homeSystem == "x86_64-linux";
  sharedAppServerSocket = "unix://\${XDG_RUNTIME_DIR}/codex-intercom-app-server.sock";
  upstreamCodexCliPackage = inputs.codex-cli.packages.${homeSystem}.default;
  claudeCodePackage = pkgs.callPackage ../../../../packages/claude-code { inherit inputs; };
  # The upstream Nix package wraps its native executable with an identity that
  # points at an unmanaged $HOME/.local/bin path.  Preserve its closure and
  # official pinned binary, but expose `codex` as the raw Nix-owned executable
  # so ordinary invocations have no mutable-user-path identity.
  codexCliPackage = pkgs.symlinkJoin {
    name = "criomos-codex-direct";
    paths = [ upstreamCodexCliPackage ];
    postBuild = ''
      rm "$out/bin/codex"
      ln -s ${upstreamCodexCliPackage}/libexec/codex "$out/bin/codex"
    '';
    meta.mainProgram = "codex";
  };
  agentIntercom = pkgs.callPackage ../../../../packages/agent-intercom {
    inherit inputs codexCliPackage;
    codexRawCommand = "${upstreamCodexCliPackage}/libexec/codex";
    sharedAppServerSocket =
      if graphicalEnabled && graphicalSupported then sharedAppServerSocket else null;
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
    # The direct, pinned CLIs are the ordinary user commands.  Keep the
    # Intercom-specific operational entry points without letting its aliases
    # shadow either CLI.  Keep the direct Codex package in the Home union for
    # every local profile: Desktop consumes it as a configured CLI path but
    # does not publish that path itself, and the union is the closure that
    # makes ordinary `codex` available alongside Intercom.
    home.packages = [
      agentIntercomRuntime
      claudeCodePackage
      codexCliPackage
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
  (lib.optionalAttrs graphicalEnabled {
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
  })
]
