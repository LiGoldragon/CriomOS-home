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
        criomosHome.zoektIndex.machineIdentityFile = toString (pkgs.writeText "machine-id" "0123456789abcdef0123456789abcdef\n");
        criomosHome.zoektIndex.remoteWorkRoot = "/tmp/zoekt-index-offload-check-remote";
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
      pkgs.python3
      pkgs.zoekt
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

    request=$(find "$XDG_STATE_HOME/zoekt-index/requests" -mindepth 1 -maxdepth 1 -type d)
    test "$(jq -r .repository "$request/request.json")" = "$repository"
    test "$(jq -r .repositoryIdentity "$request/request.json")" = "$repository"
    test "$(jq -r .revision "$request/request.json")" = "$first"
    test "$(jq -r .indexingHost "$request/request.json")" = "index-builder.example"
    remote_work_key=$(jq -r .remoteWorkKey "$request/request.json")
    test "$(printf '%s' "$remote_work_key" | sed -n '/^[0-9a-f]\{64\}$/p')" = "$remote_work_key"
    test "$(jq -r .remoteWorkRoot "$request/request.json")" = "/tmp/zoekt-index-offload-check-remote"
    test "$(jq -r .remoteWorkPath "$request/request.json")" = "/tmp/zoekt-index-offload-check-remote/$remote_work_key"

    # The accepted request owns the commit even after its source repository
    # rewrites and prunes that history.
    printf 'amended\n' > "$repository/source"
    git -C "$repository" commit -qam amended --amend
    git -C "$repository" reflog expire --expire=now --all
    git -C "$repository" gc --prune=now
    ! git -C "$repository" cat-file -e "$first^{commit}"
    test "$(git -C "$request/source.git" rev-parse HEAD)" = "$first"

    printf 'second\n' >> "$repository/source"
    git -C "$repository" commit -qam second
    ${offload}/bin/zoekt-index-offload enqueue "$repository"
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -mindepth 2 -maxdepth 2 -name request.json -exec jq -r .revision {} \; | sort -u | wc -l)" -eq 2
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -mindepth 2 -maxdepth 2 -name request.json -exec jq -r .sequence {} \; | sort -n | tr '\n' ' ')" = "1 2 "
    test "$(find "$XDG_STATE_HOME/zoekt-index/requests" -mindepth 2 -maxdepth 2 -name request.json -exec jq -r .remoteWorkKey {} \; | sort -u | wc -l)" -eq 2

    # Exercise native per-shard rename, stale deletion, and an already-open
    # mapping surviving replacement without retaining a named generation.
    export XDG_DATA_HOME="$TMPDIR/data"
    result_one="$TMPDIR/result-one"
    result_two="$TMPDIR/result-two"
    unrelated_result="$TMPDIR/unrelated-result"
    mkdir "$result_one" "$result_two" "$unrelated_result"
    git -C "$request/source.git" remote set-url origin https://github.com/example/fixture.git
    zoekt-git-index -index "$result_one" -branches HEAD "$request/source.git"
    unrelated_repository="$TMPDIR/unrelated-repository"
    git init -q "$unrelated_repository"
    git -C "$unrelated_repository" config user.name test
    git -C "$unrelated_repository" config user.email test@localhost
    printf 'unrelated\n' > "$unrelated_repository/source"
    git -C "$unrelated_repository" add source
    git -C "$unrelated_repository" commit -qm unrelated
    git -C "$unrelated_repository" remote add origin https://github.com/example/unrelated.git
    zoekt-git-index -index "$unrelated_result" -branches HEAD "$unrelated_repository"
    ${offload}/bin/zoekt-index-offload install-shards "$unrelated_result"
    unrelated_name=$(basename "$unrelated_result"/*.zoekt)
    ${offload}/bin/zoekt-index-offload install-shards "$result_one"
    installed=$(basename "$result_one"/*.zoekt)
    native_family=$(printf '%s\n' "$installed" | sed -n 's/_v[0-9][0-9]*\.[0-9][0-9]*\.zoekt$//p')
    stale_shard="''${native_family}_v16.99999.zoekt"
    older_format_shard="''${native_family}_v15.00000.zoekt"
    cp "$XDG_DATA_HOME/zoekt/index/$installed" "$XDG_DATA_HOME/zoekt/index/$stale_shard"
    cp "$XDG_DATA_HOME/zoekt/index/$installed" "$XDG_DATA_HOME/zoekt/index/$older_format_shard"
    mkfifo "$TMPDIR/mapped" "$TMPDIR/replaced"
    python3 - "$XDG_DATA_HOME/zoekt/index/$installed" "$TMPDIR/mapped" "$TMPDIR/replaced" <<'PY' &
import hashlib, mmap, os, sys
path, mapped_event, replaced_event = sys.argv[1:]
with open(path, "rb") as source:
    old = mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ)
    digest = hashlib.sha256(old).digest()
    with open(mapped_event, "w") as event:
        event.write("mapped\n")
    with open(replaced_event) as event:
        event.read()
    assert hashlib.sha256(old).digest() == digest
    old.close()
PY
    mapper=$!
    read -r mapped < "$TMPDIR/mapped"
    printf 'third\n' >> "$repository/source"
    git -C "$repository" add source
    git -C "$repository" commit -qm third
    second=$(git -C "$repository" rev-parse HEAD)
    snapshot_two="$TMPDIR/snapshot-two.git"
    git init --bare -q "$snapshot_two"
    git -C "$snapshot_two" fetch -q --depth=1 "$repository" "$second:refs/heads/snapshot"
    git -C "$snapshot_two" symbolic-ref HEAD refs/heads/snapshot
    git -C "$snapshot_two" remote add origin https://github.com/example/fixture.git
    zoekt-git-index -index "$result_two" -branches HEAD "$snapshot_two"
    ${offload}/bin/zoekt-index-offload install-shards "$result_two"
    test ! -e "$XDG_DATA_HOME/zoekt/index/$stale_shard"
    test ! -e "$XDG_DATA_HOME/zoekt/index/$older_format_shard"
    test -e "$XDG_DATA_HOME/zoekt/index/$unrelated_name"
    printf 'replaced\n' > "$TMPDIR/replaced"
    wait "$mapper"
    ! zoekt -index_dir "$XDG_DATA_HOME/zoekt/index" first | grep -F first
    zoekt -index_dir "$XDG_DATA_HOME/zoekt/index" third | grep -F third
    test ! -e "$XDG_DATA_HOME/zoekt/index-generations"
    touch "$out"
  ''
