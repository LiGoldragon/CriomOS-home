{
  config,
  lib,
  pkgs,
  user,
  ...
}:
# zoekt: indexed code search over the git repositories under a root.
# The `zoekt` command reads the shards in ~/.local/share/zoekt/index;
# a timer re-indexes every repository's HEAD, incrementally by commit.
let
  cfg = config.criomosHome.zoektIndex;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  runner = pkgs.writeShellApplication {
    name = "zoekt-index-git";
    runtimeInputs = [
      pkgs.zoekt
      pkgs.git
      pkgs.findutils
      pkgs.coreutils
      pkgs.bash
    ];
    text = ''
      root=${lib.escapeShellArg cfg.root}
      test -d "$root" || exit 0
      index_directory="''${XDG_DATA_HOME:-$HOME/.local/share}/zoekt/index"
      mkdir -p "$index_directory"
      # shellcheck disable=SC2016
      find "$root" -maxdepth ${toString cfg.depth} -name .git -prune -print0 \
        | xargs -0 -r -n1 -P${toString cfg.jobs} sh -c \
            'zoekt-git-index -index "$0" -branches HEAD "$(dirname "$1")" >/dev/null 2>&1 || true' \
            "$index_directory"
    '';
  };
in
{
  options.criomosHome.zoektIndex = {
    root = lib.mkOption {
      type = lib.types.str;
      default = "/git";
      description = "Directory whose git repositories are indexed; a missing one indexes nothing.";
    };
    depth = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "How deep under the root a repository's .git is looked for.";
    };
    jobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Repositories indexed at once.";
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Time between re-indexes.";
    };
  };
  config = lib.mkIf (sizeAtLeast "Min") {
    home.packages = [ pkgs.zoekt ];
    systemd.user.services.zoekt-index = {
      Unit.Description = "Index the git repositories under ${cfg.root} for zoekt";
      Service = {
        Type = "oneshot";
        Nice = 15;
        IOSchedulingClass = "idle";
        ExecStart = "${runner}/bin/zoekt-index-git";
      };
    };
    systemd.user.timers.zoekt-index = {
      Unit.Description = "Re-index git repositories for zoekt every ${cfg.interval}";
      Timer = {
        OnBootSec = "5m";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
