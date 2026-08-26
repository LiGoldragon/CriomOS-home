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
    users.test-user = {
      name = "test-user";
      size.min = true;
    };
    node = {
      name = "local";
      services = [ { AgentIntercomLocal = { }; } ];
    };
  };
  noLocalHorizon = {
    users.test-user = {
      name = "test-user";
      size.min = true;
    };
    node = {
      name = "headless";
      services = [ ];
    };
  };
  graphicalHorizon = {
    users.test-user = {
      name = "test-user";
      size.min = true;
    };
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
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
in
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert localHomeConfiguration.systemd.user.services ? codex-remote-control;
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
      coi codex-raw cci claude-raw \
      codex-intercom-mcp claude-intercom-mcp codex-intercom-bridge \
      agent-intercom-fleet agent-intercom-fleet-cleanup; do
      test -x ${agentIntercom}/bin/"$executable"
    done
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude
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
    for piPeer in pi-ai pi-coding-agent pi-tui; do
      test -e ${agentIntercom}/share/agent-intercom/orchestrator/node_modules/@earendil-works/"$piPeer"
    done

    # Fleet cleanup executes the orchestrator CLI outside Pi's extension
    # resolver. Import the extension directly to prove that its Pi peers are
    # available through the packaged local Node resolution tree.
    (
      cd ${agentIntercom}/share/agent-intercom/orchestrator
      ${pkgs.nodejs}/bin/node --experimental-strip-types --input-type=module \
        -e 'await import("./src/index.ts")'
    )

    # The wrappers remain wakeable aliases whose child commands are raw,
    # pinned upstream clients.
    grep -F -- '--yolo' ${agentIntercom}/bin/coi
    grep -F ${codexCliPackage}/bin/codex ${agentIntercom}/bin/coi
    ! grep -F ${agentIntercom}/bin/codex ${agentIntercom}/bin/coi
    grep -F -- '--dangerously-skip-permissions' ${agentIntercom}/bin/cci
    grep -F ${claudeCodePackage}/bin/claude ${agentIntercom}/bin/cci
    ! grep -F ${agentIntercom}/bin/claude ${agentIntercom}/bin/cci
    test -f ${agentIntercom}/share/agent-intercom/claude/node_modules/@dataforxyz/agent-intercom-core/package.json
    grep -F 'cp -R "$claudeBuild/node_modules" "$root/claude/node_modules"' ${agentIntercomPackage}
    # Load both adapters from their deployed package root: this exercises Node
    # resolution of the copied Claude runtime, rather than merely the raw CLI.
    ${pkgs.nodejs}/bin/node --input-type=module -e '
      await import("${agentIntercom}/share/agent-intercom/claude/cci.mjs");
    ' </dev/null > "$TMPDIR/cci-adapter.log" 2>&1 &
    cciPid=$!
    sleep 1
    kill "$cciPid" 2>/dev/null || true
    wait "$cciPid" 2>/dev/null || true
    ! grep -F 'ERR_MODULE_NOT_FOUND' "$TMPDIR/cci-adapter.log"
    ${pkgs.nodejs}/bin/node --input-type=module -e '
      await import("${agentIntercom}/share/agent-intercom/claude/ccim.mjs");
    ' </dev/null > "$TMPDIR/ccim-adapter.log" 2>&1 &
    ccimPid=$!
    sleep 1
    kill "$ccimPid" 2>/dev/null || true
    wait "$ccimPid" 2>/dev/null || true
    ! grep -F 'ERR_MODULE_NOT_FOUND' "$TMPDIR/ccim-adapter.log"

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

    grep -F 'github:dataforxyz/agent-intercom-pi/b6f8f9d08c8c5ec7141a0258ce61cda59d327a20' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-codex/ea1c5b538c95b89af3fd36344396779e2eadbadb' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-claude/d62b3c85547b8b83fdfe06afb38968646fe813b8' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-opencode/9d81100ea074f68f6466656c65536504209eb060' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-orchestrator/a7e16bd4386726002ab6880b35ebacdeef00fd0d' ${flakeFile}
    grep -F 'github:dataforxyz/agent-intercom-core/8316cbab548f422ad11c78ed887fabeef94817c1' ${flakeFile}
    grep -F 'linux-arm64-0.25.0.tgz' ${flakeFile}
    ${pkgs.jq}/bin/jq -e '
      .nodes."agent-intercom-pi-src".locked.rev == "b6f8f9d08c8c5ec7141a0258ce61cda59d327a20" and
      .nodes."agent-intercom-codex-src".locked.rev == "ea1c5b538c95b89af3fd36344396779e2eadbadb" and
      .nodes."agent-intercom-claude-src".locked.rev == "d62b3c85547b8b83fdfe06afb38968646fe813b8" and
      .nodes."agent-intercom-opencode-src".locked.rev == "9d81100ea074f68f6466656c65536504209eb060" and
      .nodes."agent-intercom-orchestrator-src".locked.rev == "a7e16bd4386726002ab6880b35ebacdeef00fd0d" and
      .nodes."agent-intercom-core-src".locked.rev == "8316cbab548f422ad11c78ed887fabeef94817c1" and
      .nodes."agent-intercom-esbuild-linux-arm64-src".locked.type == "file"
    ' ${flakeLock}

    touch "$out"
  ''
