{
  pkgs,
  inputs,
  stateDirectory ? "flow-040",
  ...
}:
let
  runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
  message = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # Reuse the immutable Home declarations for client executable and home.
  # This evaluation builds no service and activates no harness environment.
  user = {
    name = "li";
    size = "Min";
  };
  clientConfiguration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs user; };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/codex-next-candidate.nix
        ../../modules/home/profiles/min/herdr.nix
        {
          home.username = user.name;
          home.homeDirectory = "/home/li";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  stableClient = clientConfiguration.criomosHome.herdr.stableCodexClientPackage;
  nextClient = clientConfiguration.criomosHome.codexNextCandidate.clientPackage;
  nextHomeName = ".codex-next-${clientConfiguration.criomosHome.codexNextCandidate.hash}";
  claude = clientConfiguration.criomos.corePackages.claude;
  herdr = clientConfiguration.criomosHome.herdr.package;
  flowId = clientConfiguration.criomos.corePackages.flowId;
  harnessOverrides = ''
    [ { claude ${claude}/bin/claude /home/li/.claude None
        [ { claude-fable-5-1 claude-fable-5-1 }
          { claude-opus-5-5 claude-opus-5-5 }
          { claude-sonnet-5-5 claude-sonnet-5-5 }
          { claude-haiku-5-5 claude-haiku-5-5 } ] }
      { codexStable ${stableClient}/bin/codex-stable-flow-client /home/li/.codex-next
        Some./home/li/.codex-next/app-server-control/app-server-control.sock
        [ { gpt-5.6-sol gpt-5.6-sol }
          { gpt-5.6-luna gpt-5.6-luna } ] }
      { codexNext ${nextClient}/bin/codex-next-flow-client /home/li/${nextHomeName}
        Some./home/li/${nextHomeName}/app-server-control/app-server-control.sock
        [ { gpt-6.1-sol gpt-6.1-sol }
          { gpt-6-sol gpt-6-sol }
          { gpt-6-luna gpt-6-luna }
          { gpt-6-astra gpt-6-astra } ] } ]
  '';
  # These are the Home-owned fields of the complete configuration candidate.
  # The rollout applies them only through Flow's revisioned FullConfigure
  # transaction, beside every preserved configuration family.
  nexus = ''{ /home/li/primary /home/li/primary/flows [ Psyche ] /run/user/1001/message/message.sock ${message}/bin/message-nexus /run/user/1001/curriculum/curriculum.sock 60 { ${herdr}/bin/herdr ${flowId}/bin/flow-id ${runtime}/bin/flow-hook } default }'';
  sendServers = ''[ { ${clientConfiguration.criomosHome.codexNextCandidate.package}/bin/codex ${message}/bin/message-mcp-send } ]'';
  renderHarnesses = pkgs.writeShellApplication {
    name = "render-declared-flow-harnesses";
    text = ''
      exec ${runtime}/bin/flow-harness-defaults ${pkgs.lib.escapeShellArg harnessOverrides}
    '';
  };
  storeCheck = pkgs.writeShellApplication {
    name = "check-declared-flow-store";
    runtimeInputs = [ pkgs.psmisc ];
    text = ''
      store="$HOME/.local/state/${stateDirectory}/flow.sema"
      if fuser "$store" >/dev/null 2>&1; then
        echo "Flow store is in use; stop its Nexus before validating or migrating it" >&2
        exit 1
      fi
      exec ${runtime}/bin/flow-store-check "{ $store }"
    '';
  };
  ready = pkgs.writeShellApplication {
    name = "wait-declared-flow-ready";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      nexus_pid="''${MAINPID:?systemd main PID required}"
      runtime_dir="''${XDG_RUNTIME_DIR:?}/flow"
      owns_listener() {
        local socket="$1" inode fd target
        [ -S "$socket" ] || return 1
        while IFS= read -r inode; do
          for fd in /proc/"$nexus_pid"/fd/*; do
            target=$(readlink "$fd" 2>/dev/null) || continue
            if [ "$target" = "socket:[$inode]" ]; then return 0; fi
          done
        done < <(awk -v socket="$socket" \
          '$4 == "00010000" && $5 == "0001" && $6 == "01" && $8 == socket { print $7 }' \
          "/proc/$nexus_pid/net/unix")
        return 1
      }
      for _attempt in $(seq 1 300); do
        if ! kill -0 "$nexus_pid" 2>/dev/null; then
          echo "Flow main process exited before readiness" >&2
          exit 1
        fi
        if owns_listener "$runtime_dir/flow.sock" && owns_listener "$runtime_dir/flow-meta.sock"; then
          exit 0
        fi
        sleep 0.1
      done
      echo "Flow main process did not own both listeners before readiness timeout" >&2
      exit 1
    '';
  };
in
pkgs.runCommand "flow-deployment"
  {
    passthru = {
      inherit
        stateDirectory
        harnessOverrides
        nexus
        sendServers
        runtime
        renderHarnesses
        storeCheck
        ready
        ;
    };
  }
  ''
    mkdir -p "$out/bin"
    for name in flow flow-meta flow-nexus flow-hook flow-harness-defaults; do
      test -x "${runtime}/bin/$name"
      ln -s "${runtime}/bin/$name" "$out/bin/$name"
    done
  ''
