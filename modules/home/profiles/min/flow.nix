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
    inherit (cfg) stateDirectory solModel;
  };
  flowStart = pkgs.callPackage ../../../../packages/flow-start {
    inherit inputs;
    herdr = config.criomosHome.herdr.package;
  };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
in
{
  options.criomosHome.flow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-03521";
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
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = cfg.package == runtime;
        message = "Flow CLI and Nexus must use the single declared Flow package";
      }
    ];
    home.packages = [
      deployment
      flowStart
    ];
    systemd.user.services.flow-nexus = {
      Unit = {
        Description = "Flow Nexus";
        Wants = [ "codex-remote-control.service" ];
        Requires = [ "curriculum-nexus.service" ];
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
        ExecStartPre = "${deployment.initialize}/bin/initialize-declared-flow";
        ExecStart = "${runtime}/bin/flow-nexus \"{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/${cfg.stateDirectory}/flow.sema }\"";
        ExecStartPost = "${deployment.ready}/bin/wait-declared-flow-ready";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
