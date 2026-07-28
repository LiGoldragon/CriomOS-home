{ inputs, pkgs, ... }:
let
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom { inherit inputs; };
  graphicalAgentIntercom = pkgs.callPackage ../../packages/agent-intercom {
    inherit inputs;
    sharedAppServerSocket = "unix://\${XDG_RUNTIME_DIR}/codex-intercom-app-server.sock";
  };
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
        inherit inputs horizon pkgs;
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
  flakeFile = ../../flake.nix;
  flakeLock = ../../flake.lock;
  desktopModuleSource = "${inputs.codex-desktop-linux}/nix/home-manager-module.nix";
  coiSource = "${inputs.agent-intercom-codex-src}/codex/coi.ts";
  coiSharedAppServerPatch = ../../packages/agent-intercom/coi-shared-app-server.patch;
  codexCliPackage = inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudeCodePackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
in
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert localHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert builtins.elem agentIntercom localHomeConfiguration.home.packages;
assert graphicalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert builtins.elem graphicalAgentIntercom graphicalHomeConfiguration.home.packages;
assert !(noLocalHomeConfiguration.home.file ? ".pi/agent/packages/agent-intercom-pi");
assert !(builtins.elem agentIntercom noLocalHomeConfiguration.home.packages);
assert !graphicalWithoutLocalRejected.success;
assert graphicalHomeConfiguration.programs.codexDesktopLinux.enable;
assert graphicalHomeConfiguration.programs.codexDesktopLinux.computerUseUi.enable;
assert graphicalHomeConfiguration.programs.codexDesktopLinux.remoteMobileControl.enable;
assert graphicalHomeConfiguration.programs.codexDesktopLinux.remoteControl.enable;
assert
  graphicalHomeConfiguration.programs.codexDesktopLinux.remoteControl.listen
  == "unix://\${XDG_RUNTIME_DIR}/codex-intercom-app-server.sock";
assert graphicalHomeConfiguration.programs.codexDesktopLinux.cliPackage == codexCliPackage;
assert
  graphicalHomeConfiguration.programs.codexDesktopLinux.remoteControl.package == codexCliPackage;
assert graphicalHomeConfiguration.systemd.user.services ? agent-intercom-codex-bridge;
assert
  graphicalHomeConfiguration.systemd.user.services.agent-intercom-codex-bridge.Unit.Requires
  == [ "codex-remote-control.service" ];
assert
  graphicalHomeConfiguration.systemd.user.services.agent-intercom-codex-bridge.Unit.BindsTo
  == [ "codex-remote-control.service" ];
assert
  graphicalHomeConfiguration.systemd.user.services.agent-intercom-codex-bridge.Unit.PartOf
  == [ "codex-remote-control.service" ];
assert
  graphicalHomeConfiguration.systemd.user.services.agent-intercom-codex-bridge.Service.Restart
  == "always";
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
    test -x ${graphicalAgentIntercom}/bin/coi
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
    grep -F 'ln -s "''${claudeCodePackage}/bin/claude" "$bin_dir/claude"' ${vscodiumModule}
    ! grep -F 'agentIntercom}/bin/claude' ${vscodiumModule}

    grep -F 'CODEX_INTERCOM_CODEX_COMMAND' ${agentIntercomPackage}
    grep -F 'CLAUDE_INTERCOM_CLAUDE_COMMAND' ${agentIntercomPackage}
    grep -F 'makeWrapper "$out/bin/coi" "$out/bin/codex"' ${agentIntercomPackage}
    grep -F -- 'coi.mjs --yolo' ${agentIntercomPackage}
    grep -F 'makeWrapper "$out/bin/cci" "$out/bin/claude"' ${agentIntercomPackage}
    grep -F -- 'cci.mjs --dangerously-skip-permissions' ${agentIntercomPackage}
    ! grep -Ei 'remote-gateway|secure-remote|agent-intercom-access|ssh|credential|secret|token|oauth|enroll|pair' ${agentIntercomPackage}

    # Desktop keeps CODEX_CLI_PATH raw while its remote-control service owns
    # the only graphical app-server. The patched coi bridge attaches to that
    # service instead of spawning another server, so Desktop, Computer Use,
    # and Mobile Control share the wakeable Intercom thread authority.
    grep -F -- '--set-default CODEX_CLI_PATH' ${desktopModuleSource}
    grep -F '"app-server"' ${desktopModuleSource}
    grep -F '"--remote-control"' ${desktopModuleSource}
    grep -F 'CODEX_INTERCOM_CODEX_COMMAND || "codex"' ${coiSource}
    grep -F 'return ["app-server", ...appServerArgs, "--listen", `unix://''${socketPath}`];' ${coiSource}
    grep -F 'const appServer = spawn(options.codexCommand' ${coiSource}
    grep -F 'sharedAppServerSocketPath' ${coiSharedAppServerPatch}
    grep -F 'CODEX_INTERCOM_APP_SERVER_SOCKET' ${coiSharedAppServerPatch}
    grep -F -- '--intercom-shared-app-server' ${coiSharedAppServerPatch}
    grep -F 'patch --directory "$root/codex"' ${agentIntercomPackage}
    grep -F 'sharedAppServerSocket' ${agentIntercomPackage}
    grep -F 'agent-intercom-codex-bridge' ${agentIntercomModule}
    grep -F 'codex-intercom-app-server.sock' ${agentIntercomModule}
    grep -F 'computerUseUi.enable = true;' ${agentIntercomModule}
    grep -F 'remoteMobileControl.enable = true;' ${agentIntercomModule}
    grep -F 'remoteControl = {' ${agentIntercomModule}
    grep -F 'CODEX_INTERCOM_APP_SERVER_SOCKET' ${graphicalAgentIntercom}/bin/coi
    ! grep -F 'CODEX_INTERCOM_APP_SERVER_SOCKET' ${agentIntercom}/bin/coi
    (
      cd ${graphicalAgentIntercom}/share/agent-intercom/codex
      ${pkgs.nodejs}/bin/node node_modules/tsx/dist/cli.mjs --test codex/coi.test.ts codex/bridge-daemon.test.ts
    )

    # This starts the raw CLI app-server in remote-control mode without a
    # Desktop process. The graphical coi wrapper has no app-server child: it
    # must attach to the established service socket and register its virtual
    # Intercom agent there.
    shared_runtime="$TMPDIR/shared-runtime"
    # Codex intentionally refuses to create its helper aliases under the
    # system temporary directory. $out is writable for this check, isolated
    # from the user, and not a temporary directory from Codex's perspective.
    shared_home="$out/shared-home"
    shared_codex_home="$shared_home/.codex"
    shared_work="$TMPDIR/shared-work"
    shared_agent_dir="$shared_runtime/agent"
    shared_log_directory="$out/logs"
    shared_app_server_log="$shared_log_directory/app-server.log"
    shared_bridge_log="$shared_log_directory/coi.log"
    mkdir -p "$shared_agent_dir" "$shared_codex_home" "$shared_work" "$shared_log_directory"
    shared_server_pid=
    shared_bridge_pid=
    shared_broker_pid=
    stop_shared_witness() {
      if [ -n "$shared_bridge_pid" ]; then
        kill -TERM "$shared_bridge_pid" 2>/dev/null || true
        wait "$shared_bridge_pid" 2>/dev/null || true
      fi
      if [ -n "$shared_server_pid" ]; then
        kill -TERM "$shared_server_pid" 2>/dev/null || true
        wait "$shared_server_pid" 2>/dev/null || true
      fi
      if [ -n "$shared_broker_pid" ]; then
        kill -TERM "$shared_broker_pid" 2>/dev/null || true
        wait "$shared_broker_pid" 2>/dev/null || true
      fi
    }
    report_shared_witness_result() {
      shared_witness_status=$?
      trap - EXIT
      stop_shared_witness
      if [ "$shared_witness_status" -ne 0 ]; then
        printf '%s\n' 'Agent Intercom shared app-server witness failed; retained logs follow:'
        for shared_witness_log in "$shared_app_server_log" "$shared_bridge_log"; do
          printf '%s\n' "--- $shared_witness_log ---"
          if [ -f "$shared_witness_log" ]; then
            cat "$shared_witness_log" || true
          else
            printf '%s\n' 'log was not created'
          fi
        done
      fi
      exit "$shared_witness_status"
    }
    trap report_shared_witness_result EXIT
    HOME="$shared_home" CODEX_HOME="$shared_codex_home" XDG_RUNTIME_DIR="$shared_runtime" \
      ${codexCliPackage}/bin/codex app-server --remote-control \
        --listen "unix://$shared_runtime/codex-intercom-app-server.sock" \
        > "$shared_app_server_log" 2>&1 &
    shared_server_pid=$!
    for attempt in $(${pkgs.coreutils}/bin/seq 1 100); do
      [ -S "$shared_runtime/codex-intercom-app-server.sock" ] && break
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    test -S "$shared_runtime/codex-intercom-app-server.sock"
    HOME="$shared_home" CODEX_HOME="$shared_codex_home" CODEX_INTERCOM_DEBUG=1 PI_CODING_AGENT_DIR="$shared_agent_dir" XDG_RUNTIME_DIR="$shared_runtime" \
      ${graphicalAgentIntercom}/bin/coi --no-tui \
        --intercom-shared-app-server "unix://$shared_runtime/codex-intercom-app-server.sock" \
        --intercom-id desktop-shared-app-server-witness \
        --intercom-name 'Desktop shared app-server witness' \
        --cwd "$shared_work" \
        > "$shared_bridge_log" 2>&1 &
    shared_bridge_pid=$!
    for attempt in $(${pkgs.coreutils}/bin/seq 1 100); do
      if ${pkgs.gnugrep}/bin/grep -F 'codex-intercom bridge running 1 virtual agent(s)' "$shared_bridge_log" > /dev/null \
        && ${pkgs.gnugrep}/bin/grep -F 'coi intercom session: Desktop shared app-server witness (desktop-shared-app-server-witness)' "$shared_bridge_log" > /dev/null; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    ${pkgs.gnugrep}/bin/grep -F 'codex-intercom bridge running 1 virtual agent(s)' "$shared_bridge_log"
    ${pkgs.gnugrep}/bin/grep -F 'coi intercom session: Desktop shared app-server witness (desktop-shared-app-server-witness)' "$shared_bridge_log"
    test -s "$shared_agent_dir/intercom/broker.pid"
    shared_broker_pid=$(cat "$shared_agent_dir/intercom/broker.pid")
    # A remote-control restart must close the attach-only bridge.  The user
    # service has Restart=always and BindsTo=codex-remote-control, so it will
    # attach again only after that shared owner is available.
    kill -TERM "$shared_server_pid"
    wait "$shared_server_pid" || true
    shared_server_pid=
    for attempt in $(${pkgs.coreutils}/bin/seq 1 100); do
      ! kill -0 "$shared_bridge_pid" 2>/dev/null && break
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    ! kill -0 "$shared_bridge_pid" 2>/dev/null
    wait "$shared_bridge_pid"
    shared_bridge_pid=

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

  ''
