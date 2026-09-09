{ pkgs, inputs, ... }:
let
  modulePath = ../../modules/home/profiles/min/codex-artifact-gateway.nix;
  mkConfiguration =
    extra:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        modulePath
        {
          home = {
            username = "gateway-test";
            homeDirectory = "/home/gateway-test";
            stateVersion = "26.05";
          };
        }
        extra
      ];
    }).config;
  disabled = mkConfiguration { };
  enabled = mkConfiguration {
    services.codexArtifactGateway = {
      enable = true;
      bindAddress = "100.64.0.12";
      tlsCertificate = "/run/credentials/gateway.crt";
      tlsPrivateKey = "/run/credentials/gateway.key";
      brokerSocket = "/run/user/1001/artifact-broker.sock";
    };
  };
  service = enabled.systemd.user.services.codex-artifact-gateway.Service;
in
assert !(disabled.systemd.user.services ? codex-artifact-gateway);
assert service.UMask == "0077";
assert service.Restart == "on-failure";
assert builtins.length service.ExecStart == 1;
pkgs.runCommand "codex-artifact-gateway-module-contract" { } ''
  touch "$out"
''
