{
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
  testingConfig = pkgs.writeText "opencode-testing.json" (builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    share = "disabled";
    permission.bash = "ask";
  });
  credentialLauncher = pkgs.writeText "opencode-testing-launch.py" ''
    import os
    import sys

    credential_path = sys.argv[1]
    opencode = sys.argv[2]
    hostname = sys.argv[3]

    with open(credential_path, "rb") as credential_file:
        password = credential_file.read()
    if not password:
        raise SystemExit("OpenCode server credential is empty")

    environment = dict(os.environ)
    environment.pop("CREDENTIALS_DIRECTORY", None)
    environment["OPENCODE_SERVER_PASSWORD"] = password.decode("utf-8")
    os.execvpe(opencode, [opencode, "serve", "--hostname", hostname, "--port", "4096"], environment)
  '';
  runner = pkgs.writeShellApplication {
    name = "opencode-testing-server";
    runtimeInputs = [ pkgs.python3 pkgs.opencode ];
    text = ''
      set -eu
      credential_path="$CREDENTIALS_DIRECTORY/opencode-server-password"
      test -r "$credential_path"
      exec ${pkgs.python3}/bin/python ${credentialLauncher} "$credential_path" ${pkgs.opencode}/bin/opencode ${lib.escapeShellArg yggAddress}
    '';
  };
  login = pkgs.writeShellApplication {
    name = "opencode-testing-login";
    runtimeInputs = [ pkgs.opencode ];
    text = ''
      export OPENCODE_CONFIG=${lib.escapeShellArg testingConfig}
      exec ${pkgs.opencode}/bin/opencode "$@"
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

    # This overlay is loaded after the existing user config, leaving its protected
    # state, plugins, and other policy untouched while forcing this POC's policy.
    home.packages = [ login ];

    systemd.user.services.opencode-testing = {
      Unit = {
        Description = "OpenCode testing server on the Criome Tailnet";
        ConditionPathExists = credentialSource;
      };
      Service = {
        Type = "simple";
        WorkingDirectory = "%S/opencode-testing/scratch";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %S/opencode-testing/scratch";
        Environment = [ "OPENCODE_CONFIG=${testingConfig}" ];
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
