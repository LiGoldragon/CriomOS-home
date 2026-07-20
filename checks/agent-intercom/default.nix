{ inputs, pkgs, ... }:
let
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
  pi = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi;
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
  agentIntercomPackage = ../../packages/agent-intercom/default.nix;
  agentIntercomHorizon = {
    node = {
      name = "gateway";
      criomeDomainName = "gateway.cluster.invalid";
      services = [ { AgentIntercomGateway = { }; } ];
    };
    exNodes.peer = {
      name = "peer";
      criomeDomainName = "peer.cluster.invalid";
      services = [ { AgentIntercomPeer = { }; } ];
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
          agentIntercomGatewaySshPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA";
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
  homeConfiguration = mkHomeConfiguration agentIntercomHorizon;
  noTransportHomeConfiguration = mkHomeConfiguration {
    node = {
      name = "ordinary";
      criomeDomainName = "ordinary.cluster.invalid";
      services = [ ];
    };
  };
  flakeFile = ../../flake.nix;
  flakeLock = ../../flake.lock;
in
assert homeConfiguration.programs.codexDesktopLinux.enable;
assert homeConfiguration.programs.codexDesktopLinux.computerUseUi.enable;
assert homeConfiguration.programs.codexDesktopLinux.remoteMobileControl.enable;
assert homeConfiguration.systemd.user.services ? agent-intercom-remote-peer;
assert homeConfiguration.systemd.user.services.agent-intercom-remote-peer.Service ? ExecCondition;
assert noTransportHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert noTransportHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert !(noTransportHomeConfiguration.systemd.user.services ? agent-intercom-remote-peer);
assert !noTransportHomeConfiguration.programs.codexDesktopLinux.enable;
pkgs.runCommand "agent-intercom-home-contract"
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

    test -x ${agentIntercom}/bin/codex-intercom-mcp
    test -x ${agentIntercom}/bin/claude-intercom-mcp
    test -x ${agentIntercom}/bin/agent-intercom-fleet
    test -x ${agentIntercom}/bin/agent-intercom-access
    test -f ${agentIntercom}/share/agent-intercom/opencode/dist/plugin.mjs
    test -f ${agentIntercom}/share/agent-intercom/opencode/dist/tui.mjs
    test -f ${agentIntercom}/share/agent-intercom/pi/index.ts
    test -f ${agentIntercom}/share/agent-intercom/pi/skills/pi-intercom/SKILL.md
    test -f ${agentIntercom}/share/agent-intercom/claude/claude-server.mjs
    test -f ${agentIntercom}/share/agent-intercom/secure-remote-tunnel.sh

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
        > "$TMPDIR/pi-intercom-commands.json"
    grep -F '"name":"intercom"' "$TMPDIR/pi-intercom-commands.json"
    grep -F '"name":"intercom-id"' "$TMPDIR/pi-intercom-commands.json"

    grep -F 'remote-gateway.sock' ${agentIntercom}/share/agent-intercom/secure-remote-tunnel.sh
    grep -F -- '-R "$REMOTE_SOCK:$LOCAL_SOCK"' ${agentIntercom}/share/agent-intercom/secure-remote-tunnel.sh
    ! grep -F -- '-R "$REMOTE_SOCK:$HOME/.pi/agent/intercom/broker.sock"' \
      ${agentIntercom}/share/agent-intercom/secure-remote-tunnel.sh

    grep -F 'AgentIntercomGateway' ${agentIntercomModule}
    grep -F 'AgentIntercomPeer' ${agentIntercomModule}
    grep -F 'agentIntercomGatewaySshPubKey' ${agentIntercomModule}
    grep -F 'AGENT_INTERCOM_LOCAL_REMOTE_GATEWAY' ${agentIntercomModule}
    grep -F 'remote-gateway.sock' ${agentIntercomModule}
    grep -F 'peer-side compatibility endpoint' ${agentIntercomModule}
    grep -F 'ExecCondition' ${agentIntercomModule}
    grep -F 'ssh-keygen -y' ${agentIntercomModule}
    grep -F 'codex-intercom-mcp' ${agentIntercomModule}
    grep -F 'claude-intercom-mcp' ${agentIntercomModule}
    grep -F 'opencode/dist/plugin.mjs' ${agentIntercomModule}
    grep -F 'computerUseUi.enable = true;' ${agentIntercomModule}
    grep -F 'remoteMobileControl.enable = true;' ${agentIntercomModule}
    grep -F 'remoteControl = {' ${agentIntercomModule}
    ! grep -E 'prometheus|ouranos|zeus|tiger' ${agentIntercomModule}

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
      .nodes."agent-intercom-core-src".locked.rev == "cb5d2212912db0cd8abbb16ab08e4b539424a05d"
    ' ${flakeLock}

    grep -F 'agentIntercomCore' ${agentIntercomPackage}
    grep -F 'inputs.agent-intercom-core-src' ${agentIntercomPackage}
    ! grep -E 'fetchurl|curl|npm install' ${agentIntercomPackage}

    touch "$out"
  ''
