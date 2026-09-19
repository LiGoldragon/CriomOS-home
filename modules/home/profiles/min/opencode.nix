{
  config,
  lib,
  pkgs,
  horizon,
  ...
}:

let
  capabilities = horizon.node.capabilities or [ ];
  enabled = lib.any (capability: (capability.kind or null) == "openCodeTesting") capabilities;
  yggAddress = horizon.node.keys.yggdrasil.address or null;
  credentialSource = "/run/secrets/opencodeServerPassword";
  runner = pkgs.writeShellApplication {
    name = "opencode-testing-server";
    runtimeInputs = [ pkgs.coreutils pkgs.opencode ];
    text = ''
      set -eu
      credential_path="$CREDENTIALS_DIRECTORY/opencode-server-password"
      test -r "$credential_path"
      export OPENCODE_SERVER_PASSWORD="$(cat "$credential_path")"
      exec ${pkgs.opencode}/bin/opencode serve --hostname ${lib.escapeShellArg yggAddress} --port 4096
    '';
  };
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = yggAddress != null;
        message = "OpenCodeTesting requires the projected Criome Tailnet address";
      }
    ];

    xdg.configFile."opencode/opencode.jsonc".text = builtins.toJSON {
      share = "disabled";
    };

    systemd.user.services.opencode-testing = {
      Unit = {
        Description = "OpenCode testing server on the Criome Tailnet";
        ConditionPathExists = credentialSource;
      };
      Service = {
        Type = "simple";
        WorkingDirectory = "%S/opencode-testing/scratch";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %S/opencode-testing/scratch";
        LoadCredential = [ "opencode-server-password:${credentialSource}" ];
        ExecStart = "${runner}/bin/opencode-testing-server";
        Restart = "on-failure";
        RestartSec = "2s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
