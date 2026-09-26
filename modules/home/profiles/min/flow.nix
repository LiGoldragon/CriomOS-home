{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib)
    makeBinPath
    mkIf
    mkOption
    optional
    ;
  inherit (lib.types) bool nullOr package str;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  cfg = config.criomosHome.flow;
  system = pkgs.stdenv.hostPlatform.system;
  flowPackage = inputs.flow.packages.${system}.default;
  stableCodexClient =
    config.criomosHome.herdr.stableCodexClientPackage or config.criomos.corePackages.codex;
  nextCodexClient =
    config.criomosHome.codexNext.clientPackage or config.criomos.corePackages.codex;
  flowRuntimePath = makeBinPath [
    (config.criomosHome.herdr.package or inputs.herdr.packages.${system}.herdr)
    inputs.harness.packages.${system}.default
    config.criomos.corePackages.codex
    config.criomos.corePackages.claude
  ];

  # Flow 0.16.0 takes its whole policy through one privileged request and
  # through nothing else: the deployment environment carries only the source
  # root and the two Codex endpoints (FLOW_*), while `MetaAspects` and
  # `MessageNexusPath` exist solely in the meta `Configuration`, seeded with
  # defaults on a fresh store and replaced only by `flow-meta 'Configure.…'`.
  # A Message Nexus is therefore admitted on Flow's meta socket only once
  # this request has been made, which is why Home declares it as a unit
  # rather than leaving it to a hand-run command.
  #
  # `Configure` replaces the record whole, so every field is stated. The
  # sockets are Flow's own defaults under the user runtime directory (%t,
  # which systemd expands inside ExecStart), the codex endpoints repeat the
  # values the Nexus unit already exports, and the harness profiles are the
  # keymaps witnessed on this cluster: Claude in vim mode interrupts on two
  # Escapes and submits with Enter, Codex interrupts on one Escape and needs
  # no submit key because `agent prompt` submits for it.
  codexEndpointDatom = client: home: models: "{ ${client} ${home} ${home}/app-server-control/app-server-control.sock [ ${lib.concatStringsSep " " models} ] }";
  configureDatom = lib.concatStringsSep " " [
    "Configure.{"
    "%t/flow/flow.sock"
    "%t/flow/flow-meta.sock"
    "/home/li/primary"
    (codexEndpointDatom "${stableCodexClient}/bin/codex-stable-flow-client" "/home/li/.codex" [
      "gpt-5.6-terra"
      "gpt-5.6-sol"
      "gpt-5.6-luna"
    ])
    (codexEndpointDatom "${nextCodexClient}/bin/codex-next-flow-client" "/home/li/.codex-next" [
      "gpt-6-sol"
      "gpt-6-luna"
      "gpt-6-astra"
    ])
    "[ { Claude [ / «!» # ] [ esc esc ] [ enter ] } { Codex [ / «!» ] [ esc ] [] } ]"
    "[ Psyche ]"
    cfg.messageNexusPath
    "}"
  ];

  # The Nexus is Type=simple, so its meta socket appears shortly after the
  # process starts. The request waits on that socket — the event it needs —
  # bounded so a Nexus that never listens fails the unit instead of hanging.
  configureScript = pkgs.writeShellScript "flow-configure" ''
    set -eu
    socket="$1"
    shift
    attempt=0
    while [ ! -S "$socket" ]; do
      attempt=$((attempt + 1))
      if [ "$attempt" -gt 300 ]; then
        echo "flow-configure: $socket never appeared" >&2
        exit 1
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    reply="$(FLOW_META_SOCKET="$socket" ${cfg.package}/bin/flow-meta "$@")"
    echo "$reply"
    case "$reply" in
      Configured.*) exit 0 ;;
      *) echo "flow-configure: Flow refused the configuration" >&2; exit 1 ;;
    esac
  '';
in
{
  options.criomosHome.flow = {
    enable = mkOption {
      type = bool;
      default = config.home.username == "li";
      description = "Install and supervise a validated Flow Nexus package.";
    };
    package = mkOption {
      type = nullOr package;
      default = flowPackage;
      description = "Immutable Flow package selected after remote build and store compatibility checks.";
    };
    messageNexusPath = mkOption {
      type = str;
      default = "";
      description = "The message-nexus executable Flow admits on its meta socket, as Flow reads it back from /proc/<pid>/exe. Empty admits no Nexus by path. Set by profiles/min/message.nix.";
    };
  };

  config = {
    assertions = [
      {
        assertion = !cfg.enable || cfg.package != null;
        message = "criomosHome.flow.package must be set before Flow Nexus is enabled";
      }
      {
        assertion = !cfg.enable || config.home.username == "li";
        message = "Flow Nexus currently uses fixed li/1001 state and socket paths; it cannot be enabled for another user";
      }
    ];

    home.packages = mkIf (sizeAtLeast "Min" && cfg.enable) (optional (cfg.package != null) cfg.package);

    systemd.user.services.flow-nexus = mkIf (sizeAtLeast "Min" && cfg.enable && cfg.package != null) {
      Unit = {
        Description = "Flow Nexus";
        After = [ "codex-remote-control.service" ];
        Requires = [ "codex-remote-control.service" ];
      };
      Service = {
        Type = "simple";
        RuntimeDirectory = "flow";
        RuntimeDirectoryMode = "0700";
        Environment = [
          "FLOW_SOURCE_ROOT=/home/li/primary"
          "FLOW_CODEX_STABLE_CLIENT=${stableCodexClient}/bin/codex-stable-flow-client"
          "FLOW_CODEX_STABLE_SOCKET=/home/li/.codex/app-server-control/app-server-control.sock"
          "FLOW_CODEX_STABLE_HOME=/home/li/.codex"
          "FLOW_CODEX_STABLE_MODELS=gpt-5.6-terra,gpt-5.6-sol,gpt-5.6-luna"
          "FLOW_CODEX_NEXT_CLIENT=${nextCodexClient}/bin/codex-next-flow-client"
          "FLOW_CODEX_NEXT_SOCKET=/home/li/.codex-next/app-server-control/app-server-control.sock"
          "FLOW_CODEX_NEXT_HOME=/home/li/.codex-next"
          "FLOW_CODEX_NEXT_MODELS=gpt-6-sol,gpt-6-luna,gpt-6-astra"
          "PATH=${flowRuntimePath}"
        ];
        ExecStart = "${cfg.package}/bin/flow-nexus";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # One privileged request, made where no flow's pane holds it, so Flow
    # resolves the caller as the owner and admits it. It is idempotent: the
    # same Configuration written again is the same record.
    systemd.user.services.flow-configuration =
      mkIf (sizeAtLeast "Min" && cfg.enable && cfg.package != null)
        {
          Unit = {
            Description = "Flow Nexus configuration — MetaAspects and the admitted Message Nexus";
            After = [ "flow-nexus.service" ];
            Requires = [ "flow-nexus.service" ];
            PartOf = [ "flow-nexus.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${configureScript} %t/flow/flow-meta.sock ${lib.escapeShellArg configureDatom}";
          };
          Install.WantedBy = [ "default.target" ];
        };
  };
}
