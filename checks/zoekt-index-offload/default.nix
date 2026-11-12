{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  configuration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      user.size = "Min";
    };
    modules = [
      ../../modules/home/profiles/min/zoekt-index.nix
      {
        home = {
          username = "zoekt-index-offload-check";
          homeDirectory = "/tmp/zoekt-index-offload-check";
          stateVersion = "26.05";
        };
        criomosHome.zoektIndex.indexingHost = "index-builder.example";
      }
    ];
  };
  cfg = configuration.config;
  packageNamed =
    name: lib.findFirst (package: (package.pname or package.name) == name) null cfg.home.packages;
  offload = packageNamed "zoekt-index-offload";
in
assert offload != null;
assert
  builtins.head cfg.systemd.user.services.zoekt-index-drain.Service.ExecStart
  == "${offload}/bin/zoekt-index-offload drain";
assert
  cfg.systemd.user.paths.zoekt-index-drain.Path.PathChanged == "%h/.local/state/zoekt-index/requests";
assert lib.hasInfix "zoekt-index-repository" cfg.programs.git.settings.hook.zoekt-index.command;
pkgs.runCommand "zoekt-index-offload"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.jq
    ];
  }
  ''
    set -eu
    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$TMPDIR/state"
    repository="$TMPDIR/repository"
    mkdir -p "$HOME" "$repository"
    git -C "$repository" init -q
    git -C "$repository" config user.name test
    git -C "$repository" config user.email test@localhost
    printf 'first\n' > "$repository/source"
    git -C "$repository" add source
    git -C "$repository" commit -qm first
    first=$(git -C "$repository" rev-parse HEAD)
    ${offload}/bin/zoekt-index-offload enqueue "$repository"

    request=$(find "$XDG_STATE_HOME/zoekt-index/requests" -type f -name '*.json')
    test "$(jq -r .repository "$request")" = "$repository"
    test "$(jq -r .repositoryIdentity "$request")" = "$repository"
    test "$(jq -r .revision "$request")" = "$first"

    printf 'second\n' >> "$repository/source"
    git -C "$repository" commit -qam second
    ${offload}/bin/zoekt-index-offload enqueue "$repository"
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -type f -name '*.json' | wc -l)" -eq 2
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -type f -name '*.json' -exec jq -r .revision {} \; | sort -u | wc -l)" -eq 2
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -type f -name '*.json' -exec jq -r .sequence {} \; | sort -n | tr '\n' ' ')" = "1 2 "
    touch "$out"
  ''
