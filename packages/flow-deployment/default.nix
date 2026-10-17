{ pkgs, inputs, ... }:
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
  initialize = pkgs.writeShellApplication {
    name = "initialize-declared-flow";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      state="$HOME/.local/state/flow-production"
      runtime_dir="''${XDG_RUNTIME_DIR:?}/flow"
      store="$state/flow.sema"
      mkdir -p "$state" "$runtime_dir"
      chmod 700 "$state" "$runtime_dir"
      start="{ $runtime_dir/flow.sock $runtime_dir/flow-meta.sock $store }"
      ${runtime}/bin/flow-nexus --configure-only "$start" &
      child=$!
      trap 'kill "$child" 2>/dev/null || true' EXIT
      # A stale pathname is not readiness. Observe the listening socket
      # held by this exact child without consuming its one request.
      child_listens() {
        local inode fd target
        [ -S "$runtime_dir/flow-meta.sock" ] || return 1
        while IFS= read -r inode; do
          for fd in /proc/"$child"/fd/*; do
            target=$(readlink "$fd" 2>/dev/null) || continue
            if [ "$target" = "socket:[$inode]" ]; then return 0; fi
          done
        done < <(awk -v socket="$runtime_dir/flow-meta.sock" \
          '$4 == "00010000" && $5 == "0001" && $6 == "01" && $8 == socket { print $7 }' \
          "/proc/$child/net/unix")
        return 1
      }
      for _attempt in $(seq 1 100); do
        if child_listens; then break; fi
        if ! kill -0 "$child" 2>/dev/null; then
          status=0
          wait "$child" || status=$?
          echo "Flow configuration child exited before socket readiness (status $status)" >&2
          if [ "$status" -eq 0 ]; then exit 1; else exit "$status"; fi
        fi
        sleep 0.05
      done
      child_listens
      FLOW_META_SOCKET="$runtime_dir/flow-meta.sock" ${runtime}/bin/flow-meta \
        "Configure.Nexus.{ $HOME/primary { ${stableClient}/bin/codex-stable-flow-client $HOME/.codex-next $HOME/.codex-next/app-server-control/app-server-control.sock [ gpt-5.6-sol gpt-5.6-luna ] } { ${nextClient}/bin/codex-next-flow-client $HOME/${nextHomeName} $HOME/${nextHomeName}/app-server-control/app-server-control.sock [ gpt-6.1-sol gpt-6-sol gpt-6-luna gpt-6-astra ] } [ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ] [ Psyche ] $XDG_RUNTIME_DIR/message/message.sock ${message}/bin/message-nexus 60 }"
      wait "$child"
      trap - EXIT
    '';
  };
  leaveOutDefaults = pkgs.writeShellApplication {
    name = "configure-declared-flow-leave-outs";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      queries=$(mktemp)
      trap 'rm -f "$queries"' EXIT
      ${pkgs.babashka}/bin/bb ${./leave-outs.clj} ${inputs.primary}/config/main-flow > "$queries"
      FLOW_META_SOCKET="''${XDG_RUNTIME_DIR:?}/flow/flow-meta.sock" \
        ${pkgs.bash}/bin/bash ${./apply-leave-outs.sh} ${runtime}/bin/flow-meta "$queries"
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
          ${leaveOutDefaults}/bin/configure-declared-flow-leave-outs
          exit 0
        fi
        sleep 0.1
      done
      echo "Flow main process did not own both listeners before readiness timeout" >&2
      exit 1
    '';
  };
  unit = pkgs.writeText "flow-nexus.service" ''
    [Unit]
    Description=Flow Nexus
    Wants=codex-remote-control.service
    Requires=curriculum-nexus.service
    After=codex-remote-control.service curriculum-nexus.service
    [Service]
    Type=simple
    Environment=PATH=%h/.local/bin:%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin
    ExecStartPre=${initialize}/bin/initialize-declared-flow
    ExecStart=${runtime}/bin/flow-nexus "{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-production/flow.sema }"
    ExecStartPost=${ready}/bin/wait-declared-flow-ready
    Restart=on-failure
    RestartSec=2
    [Install]
    WantedBy=default.target
  '';
in
pkgs.runCommand "flow-deployment"
  {
    passthru = {
      inherit
        runtime
        unit
        initialize
        ready
        leaveOutDefaults
        ;
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/systemd/user"
    for name in flow flow-meta flow-nexus flow-hook; do
      test -x "${runtime}/bin/$name"
      ln -s "${runtime}/bin/$name" "$out/bin/$name"
    done
    cp ${unit} "$out/share/systemd/user/flow-nexus.service"
  ''
