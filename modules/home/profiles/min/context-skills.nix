{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.contextSkills;
  regenerate = pkgs.callPackage ../../../../packages/context-skills { };
  mains = map (name: "${config.home.homeDirectory}/primary/repos/${name}/.git/refs") [
    "psyche-context"
    "mind-context"
    "field-context"
  ];
in
{
  options.criomosHome.contextSkills.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.criomosHome.curriculum.enable;
    description = "Keep every context module installed as a skill in the Primary workspace's harness skill directories, regenerated from main on every change to main.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ regenerate ];

    systemd.user.services.context-skills = {
      Unit.Description = "Regenerate Primary workspace skills from context main";
      Service = {
        Type = "oneshot";
        ExecStart = "${regenerate}/bin/context-skills-regenerate";
      };
    };

    # A change to refs/heads/main (a commit or a fast-forward) or to
    # refs/remotes/origin/main (a fetch or push) of any of the three repositories.
    systemd.user.paths.context-skills = {
      Unit.Description = "Watch context main refs";
      Path = {
        PathChanged = lib.concatMap (refs: [
          "${refs}/heads/main"
          "${refs}/remotes/origin/main"
        ]) mains;
        Unit = "context-skills.service";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Backstop for a push from another machine, which moves no local ref
    # until fetched.
    systemd.user.timers.context-skills = {
      Unit.Description = "Fetch context main periodically";
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = "2min";
        Unit = "context-skills.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
