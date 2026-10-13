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
  deployment = pkgs.callPackage ../../../../packages/flow-deployment { inherit inputs; };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
in
{
  options.criomosHome.flow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
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
    home.packages = [ deployment ];
    systemd.user.services.flow-nexus = {
      Unit = {
        Description = "Flow Nexus";
        Wants = [ "codex-remote-control.service" ];
        After = [ "codex-remote-control.service" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "PATH=%h/.local/bin:%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
        ];
        ExecStartPre = "${deployment.initialize}/bin/initialize-declared-flow";
        ExecStart = "${runtime}/bin/flow-nexus \"Start.{ %t/flow/flow.sock %t/flow/flow-meta.sock %h/.local/state/flow-production/flow.sema }\"";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
