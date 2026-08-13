{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  esbuildCompanion =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
    }
    .${system};
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
  pi = inputs.self.packages.${system}.pi;
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
  agentIntercomPackage = ../../packages/agent-intercom/default.nix;
  localHorizon = {
    node = {
      name = "local";
      services = [ { AgentIntercomLocal = { }; } ];
    };
  };
  noLocalHorizon = {
    node = {
      name = "headless";
      services = [ ];
    };
  };
  graphicalHorizon = {
    node = {
      name = "unsupported-graphical";
      services = [
        { AgentIntercomLocal = { }; }
        { AgentIntercomGraphical = { }; }
      ];
    };
  };
  mkHomeConfiguration =
    horizon:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit
          inputs
          horizon
          system
          ;
        user = {
          name = "test-user";
          size.min = true;
        };
        hexis = inputs.hexis.packages.${system}.default;
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
  graphicalOnArmRejected = builtins.tryEval (
    (mkHomeConfiguration graphicalHorizon).activationPackage
  );
  flakeFile = ../../flake.nix;
  flakeLock = ../../flake.lock;
  claudeCodePackage = pkgs.callPackage ../../packages/claude-code { inherit inputs; };
  codexCliPackage = inputs.codex-cli.packages.${system}.default;
in
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert builtins.any (
  package: pkgs.lib.hasInfix "criomos-codex-direct" (toString package)
) localHomeConfiguration.home.packages;
assert builtins.elem claudeCodePackage localHomeConfiguration.home.packages;
assert !(builtins.elem agentIntercom localHomeConfiguration.home.packages);
assert !(noLocalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi");
assert !(builtins.elem agentIntercom noLocalHomeConfiguration.home.packages);
assert system != "aarch64-linux" || !graphicalOnArmRejected.success;
pkgs.runCommand "agent-intercom-local-family-contract"
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

    for executable in \
      coi codex codex-raw cci claude claude-raw \
      codex-intercom-mcp claude-intercom-mcp codex-intercom-bridge \
      agent-intercom-fleet agent-intercom-fleet-cleanup; do
      test -x ${agentIntercom}/bin/"$executable"
    done
    for artifact in \
      pi/index.ts \
      orchestrator/src/agent-fleet-cli.mjs \
      codex/dist/codex-server.mjs \
      codex/dist/bridge-daemon.mjs \
      codex/dist/coi.mjs \
      claude/claude-server.mjs \
      claude/worker-daemon.mjs \
      claude/cci.mjs \
      claude/ccim.mjs \
      opencode/dist/plugin.mjs \
      opencode/dist/tui.mjs; do
      test -f ${agentIntercom}/share/agent-intercom/"$artifact"
    done
    for tsxRuntime in pi orchestrator codex; do
      test -x ${agentIntercom}/share/agent-intercom/"$tsxRuntime"/node_modules/@esbuild/${esbuildCompanion}/bin/esbuild
    done

    # The wrappers remain wakeable aliases whose child commands are raw,
    # pinned upstream clients.
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

    grep -F 'aarch64-linux =' ${agentIntercomPackage}
    grep -F 'linux-arm64' ${agentIntercomPackage}
    grep -F 'esbuildCompanion' ${agentIntercomPackage}
    grep -F 'AgentIntercomLocal' ${agentIntercomModule}
    grep -F 'agentIntercomRuntime' ${agentIntercomModule}
    grep -F '"$out/bin/codex-raw"' ${agentIntercomModule}
    grep -F '"$out/bin/claude-raw"' ${agentIntercomModule}
    grep -F 'codex-raw' ${agentIntercomModule}
    ! grep -F '$HOME/.local/bin/codex' ${agentIntercomModule}
    grep -F 'codex-intercom-mcp' ${agentIntercomModule}
    grep -F 'claude-intercom-mcp' ${agentIntercomModule}
    grep -F 'opencode/dist/plugin.mjs' ${agentIntercomModule}
    ! grep -Ei 'Gateway|Peer|remote-gateway|tunnel|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomModule}
    ! grep -Ei 'remote-gateway|secure-remote|agent-intercom-access|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomPackage}

    grep -F 'github:dataforxyz/agent-intercom-pi/d539a5476c26679f558d74b894b902d6366770a4' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-codex/118c85391b525982f00f38a3e3b67278e20e2774' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-claude/f558e3bfa0d0df799b57f729a2be903e85760df4' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-opencode/5aea7545e00af04f2dd14a05bff69436917a4f46' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-orchestrator/fb3a74c9bf96373c82d8be31da7bae97d6ac0119' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-core/cb5d2212912db0cd8abbb16ab08e4b539424a05d' ${flakeFile}
    grep -F 'linux-arm64-0.25.0.tgz' ${flakeFile}
    ${pkgs.jq}/bin/jq -e '
      .nodes."agent-intercom-pi-src".locked.rev == "d539a5476c26679f558d74b894b902d6366770a4" and
      .nodes."agent-intercom-codex-src".locked.rev == "118c85391b525982f00f38a3e3b67278e20e2774" and
      .nodes."agent-intercom-claude-src".locked.rev == "f558e3bfa0d0df799b57f729a2be903e85760df4" and
      .nodes."agent-intercom-opencode-src".locked.rev == "5aea7545e00af04f2dd14a05bff69436917a4f46" and
      .nodes."agent-intercom-orchestrator-src".locked.rev == "fb3a74c9bf96373c82d8be31da7bae97d6ac0119" and
      .nodes."agent-intercom-core-src".locked.rev == "cb5d2212912db0cd8abbb16ab08e4b539424a05d" and
      .nodes."agent-intercom-esbuild-linux-arm64-src".locked.type == "file"
    ' ${flakeLock}

    touch "$out"
  ''
