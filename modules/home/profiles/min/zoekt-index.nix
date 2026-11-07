{
  config,
  lib,
  pkgs,
  user,
  ...
}:
# zoekt: indexed code search over the git repositories under a root.
# The `zoekt` command reads the shards in ~/.local/share/zoekt/index;
# a timer fetches every repository and re-indexes its origin's default
# branch, incrementally by commit.
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
      # Each repository is fetched and its origin's default branch indexed,
      # so a search answers what is published, whatever a checkout holds.
      # A worktree's .git is a file and is left out: its repository is
      # indexed once.
      # shellcheck disable=SC2016
      find "$root" -maxdepth ${toString cfg.depth} -name .git -type d -prune -print0 \
        | xargs -0 -r -n1 -P${toString cfg.jobs} sh -c '
            repository=$(dirname "$1")
            git -C "$repository" remote get-url origin >/dev/null 2>&1 || exit 0
            git -C "$repository" fetch --quiet origin >/dev/null 2>&1 || true
            git -C "$repository" symbolic-ref -q refs/remotes/origin/HEAD >/dev/null \
              || git -C "$repository" remote set-head origin --auto >/dev/null 2>&1 || true
            zoekt-git-index -index "$0" -prefix refs/remotes/origin/ -branches HEAD "$repository" >/dev/null 2>&1 || true
          ' "$index_directory"
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
