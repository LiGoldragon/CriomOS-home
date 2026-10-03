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
  flowPackage = inputs.flow.packages.${system}.default;
  occupied = config.home.homeDirectory == "/home/li";
  # The running stable Flow has an unregistered client.  Preserve the received
  # executable and endpoint tuple until its sessions have migrated.
  # This is the current managed fragment executable.  The service manager has
  # an older process loaded, so changing this byte would make sd-switch restart
  # that process during the very activation meant to preserve it.
  occupiedFlow = "/nix/store/j689l77bmlfmgc6ichksrqnnmdnma8ig-flow-0.14.0/bin/flow-nexus";
  occupiedStableClient = "/nix/store/0s199vn7jivakb7kqkcc2znxw4klv840-codex-stable-flow-client/bin/codex-stable-flow-client";
  occupiedNextClient = "/nix/store/x74szg3cbsn5s41nan43kfs6wb4xww61-codex-next-flow-client/bin/codex-next-flow-client";
  occupiedPath = "/nix/store/9x03bz0q0a978zrzcshrlmmb4fvcmdb6-herdr-0.8.2/bin:/nix/store/b4wzlwmzbfis6ys2b1svh531dplxxyd3-harness-0.3.4/bin:/nix/store/wdj0sc69r4n9is1idfb32vcx5739ijkh-codex-0.153.4/bin:/nix/store/qsq3lh2i05dz77dakipwy9f1fkssq1zw-claude-code-2.1.284/bin";
  flowRuntimePath = makeBinPath [
    (config.criomosHome.herdr.package or inputs.herdr.packages.${system}.herdr)
    inputs.harness.packages.${system}.default
    config.criomos.corePackages.codex
    config.criomos.corePackages.claude
  ];
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
