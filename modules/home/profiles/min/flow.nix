{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.flow;
  system = pkgs.stdenv.hostPlatform.system;
  stableRuntime = inputs.flow.packages.${system}.default;
  nextRuntime = inputs.flow-next.packages.${system}.default;
  service = import ../../../../lib/stable-next-service.nix { inherit lib; };
  slots = service.pair {
    stable = {
      unitName = "flow-nexus-04012";
      package = stableRuntime;
      ordinarySocket = "%t/flow/flow.sock";
      metaSocket = "%t/flow/flow-meta.sock";
      memory = "%h/.local/state/flow-040/flow.sema";
      pairedNexusEndpoints.curriculum = {
        unitName = "curriculum-nexus-040";
        ordinarySocket = "%t/flow40-rt/curriculum/curriculum.sock";
      };
    };
    next = {
      unitName = "flow-nexus-next-0420";
      package = nextRuntime;
      ordinarySocket = "%t/flow-042-next/flow.sock";
      metaSocket = "%t/flow-042-next/flow-meta.sock";
      memory = "%h/.local/state/flow-042-next/flow.sema";
      pairedNexusEndpoints = { };
    };
  };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  mkFlowService =
    slot:
    let
      curriculum = slot.pairedNexusEndpoints.curriculum or null;
      dependencies = lib.optional (curriculum != null) "${curriculum.unitName}.service";
    in
    {
      Unit = {
        Description = "Flow Nexus ${slot.unitName}";
        Wants = [ "codex-remote-control.service" ];
        Requires = dependencies;
        After = [ "codex-remote-control.service" ] ++ dependencies;
      };
      Service = {
        Type = "simple";
        Environment = [
          "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
          "FLOW_CORE_PRESENTATION_PROMPT=/home/li/primary/flows/9ef2c5/prompts/presentation-maker.md"
        ];
        ExecStart = "${slot.package}/bin/flow-nexus \"{ ${slot.ordinarySocket} ${slot.metaSocket} ${slot.memory} None }\"";
        Restart = "on-failure";
        RestartSec = 2;
        TimeoutStopSec = 90;
      };
      Install.WantedBy = [ "default.target" ];
    };
in
{
  options.criomosHome.flow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
    };
    stablePackage = lib.mkOption {
      type = lib.types.package;
      default = stableRuntime;
      readOnly = true;
    };
    nextPackage = lib.mkOption {
      type = lib.types.package;
      default = nextRuntime;
      readOnly = true;
    };
  };

  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = cfg.stablePackage == stableRuntime && cfg.nextPackage == nextRuntime;
        message = "Flow stable and next services use their declared immutable packages";
      }
    ];
    home.packages = [ stableRuntime ];
    home.activation.claudeLeavesRestToFlow = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs;
      hexis = inputs.hexis.packages.${system}.default;
      file = "$HOME/.claude/settings.json";
      declared.idleCompaction = false;
      modes."/idleCompaction" = "always";
    };
    systemd.user.services.${slots.stable.unitName} = mkFlowService slots.stable;
    systemd.user.services.${slots.next.unitName} = mkFlowService slots.next;
  };
}
