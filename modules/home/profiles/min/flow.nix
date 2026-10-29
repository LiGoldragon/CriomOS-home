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
  runtime = inputs.flow.packages.${system}.default;
  deployment = pkgs.callPackage ../../../../packages/flow-deployment {
    inherit inputs;
    inherit (cfg) stateDirectory;
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
      default = "flow-040";
      description = "Declared Flow store directory; previous cohorts remain untouched.";
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
      source_store=${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/${cfg.stateDirectory}/flow.sema"}
      check_directory="$(${pkgs.coreutils}/bin/mktemp -d)"
      trap '${pkgs.coreutils}/bin/rm -rf "$check_directory"' EXIT
      ${pkgs.coreutils}/bin/cp --reflink=auto "$source_store" "$check_directory/flow.sema"
      ${runtime}/bin/flow-store-check "{ $check_directory/flow.sema }"
      ${pkgs.coreutils}/bin/rm -rf "$check_directory"
      trap - EXIT
    '';
    systemd.user.services.flow-nexus = {
      Unit = {
        Description = "Flow Nexus";
        Wants = [
          "codex-remote-control.service"
          "curriculum-nexus.service"
        ];
        After = [
          "codex-remote-control.service"
          "curriculum-nexus.service"
        ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
        ];
        ExecStartPre = "${deployment.storeCheck}/bin/check-declared-flow-store";
        ExecStart = "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/${cfg.stateDirectory}/flow.sema ${landingWatch} }\"";
        ExecStartPost = "${deployment.ready}/bin/wait-declared-flow-ready";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
