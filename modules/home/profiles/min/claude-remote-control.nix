{
  config,
  lib,
  user ? {
    size.min = false;
  },
  ...
}:
let
  enabled = user.size.min or false;
  primaryWorkspace = "${config.home.homeDirectory}/primary";
  workingDirectory = config.criomos.claudeRemoteControl.workingDirectory;
  hasTrustedWorkingDirectory =
    workingDirectory != null
    && lib.hasPrefix "/" workingDirectory
    && workingDirectory != config.home.homeDirectory;
in
{
  options.criomos.claudeRemoteControl = {
    workingDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = primaryWorkspace;
      defaultText = lib.literalExpression "\${config.home.homeDirectory}/primary";
      description = "Explicit trusted directory rooted by the persistent Claude Remote Control owner.";
    };

    spawn = lib.mkOption {
      type = lib.types.enum [
        "same-dir"
        "worktree"
        "session"
      ];
      default = "same-dir";
      description = "Session creation mode for the persistent Claude Remote Control owner.";
    };
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = hasTrustedWorkingDirectory;
        message = "Enabled Claude Remote Control requires an explicit absolute workingDirectory that is not the account home.";
      }
    ];

    # Claude owns its authenticated relay and browser/mobile/Desktop clients.
    # A local Claude TUI cannot attach to this server as a thin client.
    systemd.user.services = lib.mkIf hasTrustedWorkingDirectory {
      claude-remote-control = {
        Unit.Description = "Claude Remote Control session owner";
        Service = {
          WorkingDirectory = workingDirectory;
          ExecStart = "${config.criomos.corePackages.claude}/bin/claude remote-control --spawn=${config.criomos.claudeRemoteControl.spawn} --permission-mode bypassPermissions";
          UMask = "0077";
          Restart = "always";
          RestartSec = "2s";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
