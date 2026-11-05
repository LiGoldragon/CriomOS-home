{ config, lib, pkgs, ... }:
# zoekt — indexed code search over the git repositories under /git.
# The `zoekt` command reads the shards in ~/.local/share/zoekt/index;
# a timer re-indexes every repository's HEAD (incrementally, by commit).
let
  indexRoot = "/git";
  runner = pkgs.writeShellApplication {
    name = "zoekt-index-git";
    runtimeInputs = [ pkgs.zoekt pkgs.git pkgs.findutils pkgs.coreutils ];
    text = ''
      index_directory="''${XDG_DATA_HOME:-$HOME/.local/share}/zoekt/index"
      mkdir -p "$index_directory"
      find ${indexRoot} -maxdepth 4 -name .git -prune -print0 \
        | xargs -0 -r -n1 -P4 sh -c \
            'zoekt-git-index -index "$0" -branches HEAD "$(dirname "$1")" >/dev/null 2>&1 || true' \
            "$index_directory"
    '';
  };
in {
  home.packages = [ pkgs.zoekt ];

  systemd.user.services.zoekt-index = {
    Unit.Description = "Index the git repositories under ${indexRoot} for zoekt";
    Service = {
      Type = "oneshot";
      Nice = 15;
      IOSchedulingClass = "idle";
      ExecStart = "${runner}/bin/zoekt-index-git";
    };
  };
  systemd.user.timers.zoekt-index = {
    Unit.Description = "Re-index git repositories for zoekt every 15 minutes";
    Timer = { OnBootSec = "5m"; OnUnitActiveSec = "15min"; Persistent = true; };
    Install.WantedBy = [ "timers.target" ];
  };
}
