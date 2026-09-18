{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  system = pkgs.stdenv.hostPlatform.system;
  flowPackage = inputs.flow.packages.${system}.default;

  flowProfilePackage =
    pkgs.runCommand "${flowPackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p "$out/bin"
        makeWrapper ${flowPackage}/bin/flow "$out/bin/flow" \
          --run 'export FLOW_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/flow/flow.sock"'
        makeWrapper ${flowPackage}/bin/flow-meta "$out/bin/flow-meta" \
          --run 'export FLOW_META_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/flow/flow-meta.sock"'
      '';
in
{
  options.criomosHome.flow = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Supervise the Flow Nexus as a systemd --user service.";
    };
  };

  config = mkIf config.criomosHome.flow.enable {
    home.packages = [ flowProfilePackage ];

    systemd.user.services.flow-nexus = {
      Unit = {
        Description = "Flow Nexus durable dispatch service";
        After = [ "codex-remote-control.service" ];
        Requires = [ "codex-remote-control.service" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        StateDirectory = "flow";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "flow";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${flowPackage}/bin/flow-nexus";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
