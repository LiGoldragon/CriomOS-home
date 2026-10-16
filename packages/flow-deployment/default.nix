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
    runtimeInputs = [ pkgs.coreutils ];
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
      for _attempt in $(seq 1 100); do
        if [ -S "$runtime_dir/flow-meta.sock" ]; then break; fi
        if ! kill -0 "$child" 2>/dev/null; then
          status=0
          wait "$child" || status=$?
          echo "Flow configuration child exited before socket readiness (status $status)" >&2
          if [ "$status" -eq 0 ]; then exit 1; else exit "$status"; fi
        fi
        sleep 0.05
      done
      test -S "$runtime_dir/flow-meta.sock"
      FLOW_META_SOCKET="$runtime_dir/flow-meta.sock" ${runtime}/bin/flow-meta \
        "Configure.Nexus.{ $HOME/primary { ${stableClient}/bin/codex-stable-flow-client $HOME/.codex-next $HOME/.codex-next/app-server-control/app-server-control.sock [ gpt-5.6-sol gpt-5.6-luna ] } { ${nextClient}/bin/codex-next-flow-client $HOME/${nextHomeName} $HOME/${nextHomeName}/app-server-control/app-server-control.sock [ gpt-6-sol gpt-6-luna gpt-6-astra ] } [ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ] [ Psyche ] $XDG_RUNTIME_DIR/message/message.sock ${message}/bin/message-nexus 60 }"
      wait "$child"
      trap - EXIT
    '';
  };
  unit = pkgs.writeText "flow-nexus.service" ''
    [Unit]
    Description=Flow Nexus
    Wants=codex-remote-control.service
    After=codex-remote-control.service
    [Service]
    Type=simple
    Environment=PATH=%h/.local/bin:%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin
    ExecStartPre=${initialize}/bin/initialize-declared-flow
    ExecStart=${runtime}/bin/flow-nexus "{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-production/flow.sema }"
    Restart=on-failure
    RestartSec=2
    [Install]
    WantedBy=default.target
  '';
in
pkgs.runCommand "flow-deployment" { passthru = { inherit runtime unit initialize; }; } ''
  mkdir -p "$out/bin" "$out/share/systemd/user"
  for name in flow flow-meta flow-nexus flow-hook; do
    test -x "${runtime}/bin/$name"
    ln -s "${runtime}/bin/$name" "$out/bin/$name"
  done
  cp ${unit} "$out/share/systemd/user/flow-nexus.service"
''
