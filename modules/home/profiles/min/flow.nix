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
  runtime = inputs.flow.packages.${system}.default.overrideAttrs (_: { doCheck = false; });
  deployment = pkgs.callPackage ../../../../packages/flow-deployment {
    inherit inputs runtime;
    inherit (cfg) stateDirectory solModel;
  };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  contextDeploy = pkgs.callPackage ../../../../packages/context-deploy {
    hostDeploy = cfg.landingDeployRequest;
  };
  # The approval pipeline: the Nexus watches the context repository's main
  # and deploys every landing through context-deploy.
  landingWatch =
    if cfg.landingRepository == null then
      "None"
    else
      "Some.{ ${cfg.landingRepository} ${contextDeploy}/bin/context-deploy }";
in
{
  options.criomosHome.flow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-042-next";
      description = "Declared Flow store directory; previous cohorts remain untouched.";
    };
    solModel = lib.mkOption {
      type = lib.types.enum [
        "gpt-6-sol"
        "gpt-6.1-sol"
      ];
      default = "gpt-6.1-sol";
    };
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = runtime;
    };
    landingRepository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Checkout whose main commits are landings the Flow Nexus deploys; null runs no approval pipeline (the default).";
    };
    landingDeployRequest = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The lojix-meta deploy that carries a landing to this node: the Deploy of the Home (or host) that serves the context, @CRIOMOS_REVISION@ standing for the CriomOS revision; null refuses every landing before anything is pinned.";
    };
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    # This activation installs the promoted unit definitions while the occupied
    # transient cohort keeps running. A later quiet-hours activation adopts the
    # definitions through sd-switch.
    systemd.user.startServices = false;
    assertions = [
      {
        assertion = cfg.package == runtime;
        message = "Flow CLI and Nexus must use the single declared Flow package";
      }
    ];
    home.packages = [ deployment ];
    # Flow refreshes a flow past its model's threshold when it rests, so
    # no harness compacts a resting flow. Claude Code compacts an idle
    # session of 200,000 tokens or more as its prompt cache nears expiry;
    # this turns that off for every Claude session. Its remaining automatic
    # compaction is at the window less 33,000 tokens.
    home.activation.claudeLeavesRestToFlow = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs;
      hexis = inputs.hexis.packages.${system}.default;
      file = "$HOME/.claude/settings.json";
      declared.idleCompaction = false;
      modes."/idleCompaction" = "always";
    };
    # The Flow this generation runs must open the store the running Nexus
    # holds: Flow's store refuses a Flow older than what it holds, and a
    # Nexus that cannot open it fails at every start. The check opens a
    # private copy, before anything of this generation is linked.
    home.activation.flowOpensItsStore = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
      ${runtime}/bin/flow-store-check '{ ${config.home.homeDirectory}/.local/state/${cfg.stateDirectory}/flow.sema }'
    '';
    systemd.user.services.flow-nexus-next-0420 = {
      Unit = {
        Description = "Flow Nexus 0.42 stable";
        # The transition cohort remains restartable, but may never share the
        # redb writer with the canonical cohort.
        Conflicts = [ "flow-nexus.service" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "FLOW_CORE_PRESENTATION_PROMPT=%h/primary/flows/e3c8c1/presentation-role.md"
        ];
        WorkingDirectory = "%h";
        ExecStart = "${runtime}/bin/flow-nexus \"{ «%t/flow-042-next/flow.sock» «%t/flow-042-next/flow-meta.sock» «%h/.local/state/${cfg.stateDirectory}/flow.sema» ${landingWatch} }\"";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
    };

    # The canonical cohort owns the public sockets and the same Memory file.
    # It is wanted at boot; Home's startServices=false keeps activation from
    # starting it during a generation switch. Conflicts is the declarative
    # single-writer guard for later starts.
    systemd.user.services.flow-nexus = {
      Unit = {
        Description = "Flow Nexus 0.44 canonical";
        Conflicts = [ "flow-nexus-next-0420.service" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "FLOW_CORE_PRESENTATION_PROMPT=%h/primary/flows/e3c8c1/presentation-role.md"
        ];
        WorkingDirectory = "%h";
        ExecStartPre = "${deployment}/bin/flow-canonical-bridge %t/flow-042-next %t/flow prepare";
        ExecStart = "${runtime}/bin/flow-nexus \"{ «%t/flow/flow.sock» «%t/flow/flow-meta.sock» «%h/.local/state/${cfg.stateDirectory}/flow.sema» None }\"";
        ExecStartPost = "${deployment}/bin/flow-canonical-bridge %t/flow-042-next %t/flow";
        ExecStopPost = "${deployment}/bin/flow-canonical-bridge %t/flow-042-next %t/flow remove";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
