{
  config,
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  cfg = config.criomosHome.message;
  runtime = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;
  deployment = pkgs.callPackage ../../../../packages/message-deployment { inherit inputs; };
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
in
{
  options.criomosHome.message = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.criomosHome.flow.enable;
    };
    daemonBinary = lib.mkOption {
      type = lib.types.enum [ "message-nexus" ];
      default = "message-nexus";
    };
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = config.criomosHome.flow.enable;
        message = "Message Nexus requires the declared Flow Nexus to be enabled";
      }
    ];
    home.packages = [ deployment ];
    systemd.user.services.message-nexus = {
      Unit = {
        Description = "Message Nexus";
        Requires = [ "flow-nexus.service" ];
        After = [ "flow-nexus.service" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "HOME=%h"
          "XDG_RUNTIME_DIR=%t"
        ];
        ExecStart = "${runtime}/bin/message-nexus";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
