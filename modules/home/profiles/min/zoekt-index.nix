{
  lib,
  pkgs,
  user,
  ...
}:
# zoekt: indexed code search, updated one changed repository at a time.
# The `zoekt` command reads the shards in ~/.local/share/zoekt/index;
# `zoekt-index-repository` is the post-commit/post-merge hook target.
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  runner = pkgs.writeShellApplication {
    name = "zoekt-index-repository";
    runtimeInputs = [
      pkgs.zoekt
      pkgs.git
    ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: zoekt-index-repository REPOSITORY" >&2
        exit 2
      fi
      repository=$(git -C "$1" rev-parse --show-toplevel)
      index_directory="''${XDG_DATA_HOME:-$HOME/.local/share}/zoekt/index"
      mkdir -p "$index_directory"
      exec zoekt-git-index -index "$index_directory" -branches HEAD "$repository"
    '';
  };
in
{
  config = lib.mkIf (sizeAtLeast "Min") {
    home.packages = [ pkgs.zoekt runner ];

    # Git 2.55 configuration hooks compose with repository hook files; unlike
    # core.hooksPath, this does not replace hooks owned by the repository.
    programs.git.settings.hook.zoekt-index = {
      command = "${runner}/bin/zoekt-index-repository .";
      event = [
        "post-commit"
        "post-merge"
      ];
    };
  };
}
