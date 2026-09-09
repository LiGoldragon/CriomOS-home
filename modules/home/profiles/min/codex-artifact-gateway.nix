{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.codexArtifactGateway;
  gateway = pkgs.callPackage ../../../../packages/codex-artifact-gateway { };
in
{
  options.services.codexArtifactGateway = {
    enable = mkEnableOption "the capability-authorized Codex artifact gateway";
    bindAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Tailnet interface IP address on which the TLS gateway listens.";
    };
    port = mkOption {
      type = types.port;
      default = 8443;
      description = "Tailnet TLS listener port.";
    };
    tlsCertificate = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Externally provisioned TLS certificate.";
    };
    tlsPrivateKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Externally provisioned TLS private key.";
    };
    brokerSocket = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Unix HTTP socket of the capability-authorized artifact broker.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bindAddress != null;
        message = "services.codexArtifactGateway.bindAddress must name the Tailnet interface IP";
      }
      {
        assertion = cfg.tlsCertificate != null && cfg.tlsPrivateKey != null;
        message = "services.codexArtifactGateway requires externally provisioned TLS certificate and key paths";
      }
      {
        assertion = cfg.brokerSocket != null;
        message = "services.codexArtifactGateway.brokerSocket must name the authorized broker socket";
      }
    ];

    home.packages = [ gateway ];
    systemd.user.services.codex-artifact-gateway = {
      Unit = {
        Description = "Tailnet capability artifact gateway";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe gateway)
          "--bind-address"
          (lib.escapeShellArg cfg.bindAddress)
          "--port"
          (toString cfg.port)
          "--tls-certificate"
          (lib.escapeShellArg (toString cfg.tlsCertificate))
          "--tls-private-key"
          (lib.escapeShellArg (toString cfg.tlsPrivateKey))
          "--broker-socket"
          (lib.escapeShellArg cfg.brokerSocket)
        ];
        Restart = "on-failure";
        RestartSec = "2s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        LockPersonality = true;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
