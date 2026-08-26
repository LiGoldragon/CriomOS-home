{ inputs, pkgs, ... }:
let
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
  pi = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
  agentIntercomPackage = ../../packages/agent-intercom/default.nix;
  vscodiumModule = ../../modules/home/vscodium/vscodium/default.nix;
  localHorizon = {
    users.test-user = {
      name = "test-user";
      size = {
        min = true;
        medium = true;
      };
    };
    node = {
      name = "node";
      services = [ { AgentIntercomLocal = { }; } ];
    };
  };
  noLocalHorizon = {
    users.test-user = {
      name = "test-user";
      size = {
        min = true;
        medium = true;
      };
    };
    node = {
      name = "headless";
      services = [ ];
    };
  };
  graphicalWithoutLocalHorizon = {
    users.test-user = {
      name = "test-user";
      size = {
        min = true;
        medium = true;
      };
    };
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
          size = {
            min = true;
            medium = true;
          };
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      modules = [
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
  localHomeConfiguration = mkHomeConfiguration localHorizon;
  noLocalHomeConfiguration = mkHomeConfiguration noLocalHorizon;
  graphicalWithoutLocalRejected = builtins.tryEval (
    (mkHomeConfiguration graphicalWithoutLocalHorizon).activationPackage
  );
  flakeFile = ../../flake.nix;
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
  claudeCodePackage = pkgs.callPackage ../../packages/claude-code { inherit inputs; };
  profile = pkgs.buildEnv {
    name = "agent-intercom-local-profile";
    paths = localHomeConfiguration.home.packages;
  };
  packageName = package: package.pname or (package.name or "");
  hasAgentIntercomRuntime =
    configuration:
    builtins.any (package: packageName package == "agent-intercom-runtime") configuration.home.packages;
in
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert hasAgentIntercomRuntime localHomeConfiguration;
assert !(noLocalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi");
assert !(hasAgentIntercomRuntime noLocalHomeConfiguration);
assert !graphicalWithoutLocalRejected.success;
pkgs.runCommand "agent-intercom-local-home-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.nodejs
      profile
    ];
  }
  ''
    set -eu

    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/codex-raw
    test "$( ${agentIntercom}/bin/codex-raw --version )" = 'codex-cli ${codexCliPackage.version}'
    test -x ${profile}/bin/codex
    test "$( ${profile}/bin/codex --version )" = 'codex-cli ${codexCliPackage.version}'
    test -x ${profile}/bin/claude
    test "$( ${profile}/bin/claude --version )" = '${claudeCodePackage.version} (Claude Code)'
    ! test -e ${agentIntercom}/bin/codex
    test -x ${agentIntercom}/bin/cci
    ! test -e ${agentIntercom}/bin/claude
    test -x ${agentIntercom}/bin/claude-raw
    test -x ${agentIntercom}/bin/codex-intercom-mcp
    test -x ${agentIntercom}/bin/claude-intercom-mcp
    test -x ${agentIntercom}/bin/agent-intercom-fleet
    test -f ${agentIntercom}/share/agent-intercom/opencode/dist/plugin.mjs
    test -f ${agentIntercom}/share/agent-intercom/pi/index.ts

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

    grep -F 'AgentIntercomLocal' ${agentIntercomModule}
    grep -F 'AgentIntercomGraphical' ${agentIntercomModule}
    grep -F 'codex-intercom-mcp' ${agentIntercomModule}
    grep -F 'claude-intercom-mcp' ${agentIntercomModule}
    grep -F 'opencode/dist/plugin.mjs' ${agentIntercomModule}
    ! grep -Ei 'Gateway|Peer|remote-gateway|tunnel|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomModule}
    ! grep -Ei 'no-sandbox|disable.*sandbox|sandbox.*disable' ${agentIntercomModule}
    grep -F 'ln -s "''${claudeCodePackage}/bin/claude" "$bin_dir/claude"' ${vscodiumModule}
    ! grep -F 'agentIntercom}/bin/claude' ${vscodiumModule}

    grep -F 'CODEX_INTERCOM_CODEX_COMMAND' ${agentIntercomPackage}
    grep -F 'CLAUDE_INTERCOM_CLAUDE_COMMAND' ${agentIntercomPackage}
    ! grep -F 'sharedAppServerSocket' ${agentIntercomPackage}
    ! grep -F 'coi-shared-app-server.patch' ${agentIntercomPackage}
    ! grep -F 'codex-desktop-linux' ${flakeFile}
    ${pkgs.gnugrep}/bin/grep -F 'ed38c11e34e72199025ab70dc0042d78ef4c64cd' ${flakeFile}
    ${pkgs.gnugrep}/bin/grep -F 'github:numtide/llm-agents.nix' ${flakeFile}
  ''
