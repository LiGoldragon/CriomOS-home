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
in
{
  options.criomos.claudeRemoteControl = {
    workingDirectory = lib.mkOption {
      type = lib.types.str;
      default = config.home.homeDirectory;
      defaultText = lib.literalExpression "config.home.homeDirectory";
      description = "Directory rooted by the persistent Claude Remote Control owner.";
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
        assertion = lib.hasPrefix "/" config.criomos.claudeRemoteControl.workingDirectory;
        message = "Claude Remote Control workingDirectory must be absolute.";
      }
    ];

    # Claude owns its authenticated relay and browser/mobile/Desktop clients.
    # A local Claude TUI cannot attach to this server as a thin client.
    systemd.user.services.claude-remote-control = {
      Unit.Description = "Claude Remote Control session owner";
      Service = {
        WorkingDirectory = config.criomos.claudeRemoteControl.workingDirectory;
        ExecStart = "${config.criomos.corePackages.claude}/bin/claude remote-control --spawn=${config.criomos.claudeRemoteControl.spawn}";
        UMask = "0077";
        Restart = "always";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
