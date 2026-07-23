{ inputs, pkgs, ... }:
let
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
  pi = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
  agentIntercomPackage = ../../packages/agent-intercom/default.nix;
  vscodiumModule = ../../modules/home/vscodium/vscodium/default.nix;
  localHorizon = graphical: {
    node = {
      name = "node";
      services = [
        { AgentIntercomLocal = { }; }
      ]
      ++ pkgs.lib.optional graphical {
        AgentIntercomGraphical = { };
      };
    };
  };
  noLocalHorizon = {
    node = {
      name = "headless";
      services = [ ];
    };
  };
  graphicalWithoutLocalHorizon = {
    node = {
      name = "invalid-graphical";
      services = [ { AgentIntercomGraphical = { }; } ];
    };
  };
  mkHomeConfiguration =
    horizon:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs horizon;
        user = {
          name = "test-user";
          size.min = true;
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      modules = [
        inputs.codex-desktop-linux.homeManagerModules.default
        agentIntercomModule
        {
          home = {
            username = "test-user";
            homeDirectory = "/home/test-user";
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  localHomeConfiguration = mkHomeConfiguration (localHorizon false);
  graphicalHomeConfiguration = mkHomeConfiguration (localHorizon true);
  noLocalHomeConfiguration = mkHomeConfiguration noLocalHorizon;
  graphicalWithoutLocalRejected = builtins.tryEval (
    (mkHomeConfiguration graphicalWithoutLocalHorizon).activationPackage
  );
  desktopEnabledRejected = builtins.tryEval (
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        horizon = localHorizon true;
        user = {
          name = "test-user";
          size.min = true;
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
        inherit inputs;
      };
      modules = [
        inputs.codex-desktop-linux.homeManagerModules.default
        agentIntercomModule
        {
          home = {
            username = "test-user";
            homeDirectory = "/home/test-user";
            stateVersion = "26.05";
          };
          programs.codexDesktopLinux.enable = true;
        }
      ];
    }).activationPackage
  );
  flakeFile = ../../flake.nix;
  flakeLock = ../../flake.lock;
  desktopModuleSource = "${inputs.codex-desktop-linux}/nix/home-manager-module.nix";
  coiSource = "${inputs.agent-intercom-codex-src}/codex/coi.ts";
  codexCliPackage = inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudeCodePackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
in
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert builtins.elem agentIntercom localHomeConfiguration.home.packages;
assert graphicalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert builtins.elem agentIntercom graphicalHomeConfiguration.home.packages;
assert !(noLocalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi");
assert !(builtins.elem agentIntercom noLocalHomeConfiguration.home.packages);
assert !graphicalWithoutLocalRejected.success;
assert !graphicalHomeConfiguration.programs.codexDesktopLinux.enable;
assert !graphicalHomeConfiguration.programs.codexDesktopLinux.computerUseUi.enable;
assert !graphicalHomeConfiguration.programs.codexDesktopLinux.remoteMobileControl.enable;
assert pkgs.lib.any (
  assertion:
  assertion.message
  == "Agent Intercom Desktop activation is blocked: pinned ilysenko/codex-desktop-linux wraps cliPackage as CODEX_CLI_PATH and its remote-control service invokes codex app-server, while pinned coi owns a separate raw-Codex app-server and remote TUI. CODEX_CLI_PATH must remain a drop-in raw Codex CLI; setting it to coi would misinterpret Desktop app-server arguments or create competing ownership. No supported attachment exists, so keep programs.codexDesktopLinux.enable = false. Computer Use and Mobile Control stay inactive with Desktop; ordinary MCP is not a wakeable substitute."
  && assertion.assertion
) graphicalHomeConfiguration.assertions;
assert !desktopEnabledRejected.success;
pkgs.runCommand "agent-intercom-local-home-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.nodejs
    ];
  }
  ''
    set -eu

    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/codex
    test -x ${agentIntercom}/bin/codex-raw
    test -x ${agentIntercom}/bin/cci
    test -x ${agentIntercom}/bin/claude
    test -x ${agentIntercom}/bin/claude-raw
    test -x ${agentIntercom}/bin/codex-intercom-mcp
    test -x ${agentIntercom}/bin/claude-intercom-mcp
    test -x ${agentIntercom}/bin/agent-intercom-fleet
    test -f ${agentIntercom}/share/agent-intercom/opencode/dist/plugin.mjs
    test -f ${agentIntercom}/share/agent-intercom/opencode/dist/tui.mjs
    test -f ${agentIntercom}/share/agent-intercom/pi/index.ts

    # Normal aliases carry the required dangerous defaults, while their child
    # command variables resolve to raw upstream CLIs rather than the aliases.
    grep -F -- '--yolo' ${agentIntercom}/bin/coi
    grep -F ${codexCliPackage}/bin/codex ${agentIntercom}/bin/coi
    ! grep -F ${agentIntercom}/bin/codex ${agentIntercom}/bin/coi
    grep -F -- '--dangerously-skip-permissions' ${agentIntercom}/bin/cci
    grep -F ${claudeCodePackage}/bin/claude ${agentIntercom}/bin/cci
    ! grep -F ${agentIntercom}/bin/claude ${agentIntercom}/bin/cci

    protocol_home="$TMPDIR/protocol-home"
    mkdir -p "$protocol_home" "$TMPDIR/runtime"
    (
      cd ${agentIntercom}/share/agent-intercom/pi
      HOME="$protocol_home" XDG_RUNTIME_DIR="$TMPDIR/runtime" \
        ${pkgs.nodejs}/bin/node node_modules/tsx/dist/cli.mjs \
          --test --test-concurrency=1 broker/*.test.ts
    )

    pi_home="$TMPDIR/pi-home"
    mkdir -p "$pi_home/.pi/agent" "$TMPDIR/pi-runtime"
    printf '{"type":"get_commands"}\n' | \
      HOME="$pi_home" \
      XDG_RUNTIME_DIR="$TMPDIR/pi-runtime" \
      PI_PACKAGE_DIR="${pi}/lib/pi-monorepo/packages/coding-agent" \
      ${pi}/bin/pi --mode rpc --no-session --no-context-files --no-skills \
        -e ${agentIntercom}/share/agent-intercom/pi/index.ts \
        > "$TMPDIR/agent-intercom-commands.json"
    grep -F '"name":"intercom"' "$TMPDIR/agent-intercom-commands.json"
    grep -F '"name":"intercom-id"' "$TMPDIR/agent-intercom-commands.json"

    grep -F 'AgentIntercomLocal' ${agentIntercomModule}
    grep -F 'AgentIntercomGraphical' ${agentIntercomModule}
    grep -F 'codex-intercom-mcp' ${agentIntercomModule}
    grep -F 'claude-intercom-mcp' ${agentIntercomModule}
    grep -F 'opencode/dist/plugin.mjs' ${agentIntercomModule}
    ! grep -Ei 'Gateway|Peer|remote-gateway|tunnel|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomModule}
    ! grep -Ei 'no-sandbox|disable.*sandbox|sandbox.*disable' ${agentIntercomModule}
    grep -F 'ln -s "''${agentIntercom}/bin/claude" "$bin_dir/claude"' ${vscodiumModule}

    grep -F 'CODEX_INTERCOM_CODEX_COMMAND' ${agentIntercomPackage}
    grep -F 'CLAUDE_INTERCOM_CLAUDE_COMMAND' ${agentIntercomPackage}
    grep -F 'makeWrapper "$out/bin/coi" "$out/bin/codex"' ${agentIntercomPackage}
    grep -F -- 'coi.mjs --yolo' ${agentIntercomPackage}
    grep -F 'makeWrapper "$out/bin/cci" "$out/bin/claude"' ${agentIntercomPackage}
    grep -F -- 'cci.mjs --dangerously-skip-permissions' ${agentIntercomPackage}
    ! grep -Ei 'remote-gateway|secure-remote|agent-intercom-access|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomPackage}

    # The Desktop hard gate is anchored in the pinned local sources. The
    # Desktop module turns cliPackage into CODEX_CLI_PATH and offers a separate
    # remote-control app-server; coi itself owns a raw child app-server and
    # remote TUI, so no drop-in/wakeable attachment contract exists.
    grep -F -- '--set-default CODEX_CLI_PATH' ${desktopModuleSource}
    grep -F '"app-server"' ${desktopModuleSource}
    grep -F '"--remote-control"' ${desktopModuleSource}
    grep -F 'CODEX_INTERCOM_CODEX_COMMAND || "codex"' ${coiSource}
    grep -F 'return ["app-server", ...appServerArgs, "--listen", `unix://''${socketPath}`];' ${coiSource}
    grep -F 'const appServer = spawn(options.codexCommand' ${coiSource}
    ! grep -F 'case "app-server"' ${coiSource}

    grep -F 'github:dataforxyz/agent-intercom-pi/d539a5476c26679f558d74b894b902d6366770a4' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-codex/118c85391b525982f00f38a3e3b67278e20e2774' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-claude/f558e3bfa0d0df799b57f729a2be903e85760df4' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-opencode/5aea7545e00af04f2dd14a05bff69436917a4f46' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-orchestrator/fb3a74c9bf96373c82d8be31da7bae97d6ac0119' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-core/cb5d2212912db0cd8abbb16ab08e4b539424a05d' ${flakeFile}
    ! grep -F 'github:LiGoldragon/pi-intercom' ${flakeFile}
    ${pkgs.jq}/bin/jq -e '
      .nodes."agent-intercom-pi-src".locked.rev == "d539a5476c26679f558d74b894b902d6366770a4" and
      .nodes."agent-intercom-codex-src".locked.rev == "118c85391b525982f00f38a3e3b67278e20e2774" and
      .nodes."agent-intercom-claude-src".locked.rev == "f558e3bfa0d0df799b57f729a2be903e85760df4" and
      .nodes."agent-intercom-opencode-src".locked.rev == "5aea7545e00af04f2dd14a05bff69436917a4f46" and
      .nodes."agent-intercom-orchestrator-src".locked.rev == "fb3a74c9bf96373c82d8be31da7bae97d6ac0119" and
      .nodes."agent-intercom-core-src".locked.rev == "cb5d2212912db0cd8abbb16ab08e4b539424a05d" and
      .nodes."codex-desktop-linux".locked.rev == "2b8f610faddc576088732395df3734b1d19cd62f"
    ' ${flakeLock}

    touch "$out"
  ''
