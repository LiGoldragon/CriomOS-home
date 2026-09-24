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
  inherit (lib.types) bool nullOr package;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  cfg = config.criomosHome.flow;
  system = pkgs.stdenv.hostPlatform.system;
  flowRuntimePath = makeBinPath [
    inputs.herdr.packages.${system}.herdr
    inputs.harness.packages.${system}.default
    config.criomos.corePackages.codex
    config.criomos.corePackages.claude
  ];
in
{
  options.criomosHome.flow = {
    enable = mkOption {
      type = bool;
      default = false;
      description = "Install and supervise a validated Flow Nexus package.";
    };
    package = mkOption {
      type = nullOr package;
      default = null;
      description = "Immutable Flow package selected after remote build and store compatibility checks.";
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
          "PATH=${flowRuntimePath}"
        ];
        ExecStart = "${cfg.package}/bin/flow-nexus";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
