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
    export XDG_CONFIG_HOME="$HOME/.config"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME"

    # Git runs configured hooks with its source repository context exported.
    # First show that an unisolated `git -C` still selects that source, then
    # add every repository-local override the production command must clear.
    hook_repository="$TMPDIR/hook-repository"
    hook_linked_worktree="$TMPDIR/hook-linked-worktree"
    hook_decoy="$TMPDIR/hook-decoy.git"
    hook_alternate="$TMPDIR/hook-alternate.git"
    export HOOK_CONTEXT_EVIDENCE="$TMPDIR/hook-context-evidence"
    export HOOK_DECOY="$hook_decoy"
    export HOOK_ALTERNATE_OBJECTS="$hook_alternate/objects"
    export XDG_STATE_HOME="$TMPDIR/hook-state"
    mkdir -p "$hook_repository"
    git -C "$hook_repository" init -q -b main
    git -C "$hook_repository" config user.name test
    git -C "$hook_repository" config user.email test@localhost
    printf 'base\n' > "$hook_repository/source"
    git -C "$hook_repository" add source
    git -C "$hook_repository" commit -qm base
    git -C "$hook_repository" switch -q -c ordinary-merge-source
    printf 'ordinary merge side\n' > "$hook_repository/ordinary-side"
    git -C "$hook_repository" add ordinary-side
    git -C "$hook_repository" commit -qm ordinary-merge-source
    git -C "$hook_repository" switch -q main
    git -C "$hook_repository" switch -q -c linked-merge-source
    printf 'linked merge side\n' > "$hook_repository/linked-side"
    git -C "$hook_repository" add linked-side
    git -C "$hook_repository" commit -qm linked-merge-source
    git -C "$hook_repository" switch -q main
    git -C "$hook_repository" worktree add -q -b linked-worktree "$hook_linked_worktree" HEAD
    git init --bare -q "$hook_decoy"
    git init --bare -q "$hook_alternate"
    hook_common=$(git -C "$hook_repository" rev-parse --path-format=absolute --git-common-dir)
    test ! -e "$hook_common/shallow"
    test ! -e "$hook_common/refs/heads/snapshot"

    hook_wrapper="$TMPDIR/zoekt-hook"
    cat > "$hook_wrapper" <<'HOOK'
#!/bin/sh
set -eu
source_git_directory=$(git rev-parse --absolute-git-dir)
raw_selected_directory=$(git -C "$HOOK_DECOY" rev-parse --absolute-git-dir)
if [ "$raw_selected_directory" = "$source_git_directory" ]; then
  printf 'original-context-leak %s\n' "$source_git_directory" >> "$HOOK_CONTEXT_EVIDENCE"
else
  test "$raw_selected_directory" = "$HOOK_DECOY"
  printf 'ordinary-context %s\n' "$source_git_directory" >> "$HOOK_CONTEXT_EVIDENCE"
fi
export GIT_INDEX_FILE="$(git rev-parse --path-format=absolute --git-path index)"
export GIT_COMMON_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
export GIT_OBJECT_DIRECTORY="$(git rev-parse --path-format=absolute --git-path objects)"
export GIT_ALTERNATE_OBJECT_DIRECTORIES="$HOOK_ALTERNATE_OBJECTS"
export GIT_NAMESPACE=zoekt-hook-context-check
exec ${cfg.programs.git.settings.hook.zoekt-index.command}
HOOK
    chmod +x "$hook_wrapper"
    git config --global user.name test
    git config --global user.email test@localhost
    git config --global hook.zoekt-context-check.command "$hook_wrapper"
    git config --global --add hook.zoekt-context-check.event post-commit
    git config --global --add hook.zoekt-context-check.event post-merge

    printf 'ordinary commit\n' >> "$hook_repository/source"
    git -C "$hook_repository" commit -qam ordinary-commit
    ordinary_commit=$(git -C "$hook_repository" rev-parse HEAD)
    git -C "$hook_repository" merge -q --no-edit ordinary-merge-source
    ordinary_merge=$(git -C "$hook_repository" rev-parse HEAD)
    printf 'linked commit\n' >> "$hook_linked_worktree/source"
    git -C "$hook_linked_worktree" commit -qam linked-commit
    linked_commit=$(git -C "$hook_linked_worktree" rev-parse HEAD)
    git -C "$hook_linked_worktree" merge -q --no-edit linked-merge-source
    linked_merge=$(git -C "$hook_linked_worktree" rev-parse HEAD)

    test "$(wc -l < "$HOOK_CONTEXT_EVIDENCE")" -ge 4
    grep -q '^original-context-leak ' "$HOOK_CONTEXT_EVIDENCE"
    test "$(git -C "$hook_repository" symbolic-ref --short HEAD)" = main
    test "$(git -C "$hook_linked_worktree" symbolic-ref --short HEAD)" = linked-worktree
    test -z "$(git -C "$hook_repository" status --porcelain)"
    test -z "$(git -C "$hook_linked_worktree" status --porcelain)"
    test "$(git -C "$hook_repository" write-tree)" = "$(git -C "$hook_repository" rev-parse HEAD^{tree})"
    test "$(git -C "$hook_linked_worktree" write-tree)" = "$(git -C "$hook_linked_worktree" rev-parse HEAD^{tree})"
    test ! -e "$hook_common/shallow"
    test ! -e "$hook_common/refs/heads/snapshot"
    test -z "$(git --git-dir="$hook_common" for-each-ref --format='%(refname)' refs/namespaces)"
    test "$(git -C "$hook_repository" rev-parse ordinary-merge-source)" = \
      "$(git -C "$hook_repository" rev-parse HEAD^2)"
    test "$(git -C "$hook_linked_worktree" rev-parse linked-merge-source)" = \
      "$(git -C "$hook_linked_worktree" rev-parse HEAD^2)"

    hook_requests="$XDG_STATE_HOME/zoekt-index/requests"
    test "$(find "$hook_requests" -mindepth 1 -maxdepth 1 -type d | wc -l)" -ge 4
    for intended_revision in "$ordinary_commit" "$ordinary_merge" "$linked_commit" "$linked_merge"; do
      intended_request=$(find "$hook_requests" -mindepth 2 -maxdepth 2 -name request.json \
        -exec grep -l "$intended_revision" {} \; | head -n1)
      test -n "$intended_request"
      snapshot=$(dirname "$intended_request")/source.git
      test "$(git -C "$snapshot" rev-parse HEAD)" = "$intended_revision"
      git -C "$snapshot" cat-file -e "$intended_revision^{commit}"
    done

    # A request owns its object after the installed hook's source is rewritten
    # and garbage-collected.
    printf 'ephemeral\n' >> "$hook_repository/source"
    git -C "$hook_repository" commit -qam ephemeral
    ephemeral=$(git -C "$hook_repository" rev-parse HEAD)
    ephemeral_request=$(find "$hook_requests" -mindepth 2 -maxdepth 2 -name request.json \
      -exec grep -l "$ephemeral" {} \; | head -n1)
    printf 'replacement\n' >> "$hook_repository/source"
    git -C "$hook_repository" commit -qam replacement --amend
    git -C "$hook_repository" reflog expire --expire=now --all
    git -C "$hook_repository" gc --prune=now
    ! git -C "$hook_repository" cat-file -e "$ephemeral^{commit}"
    test "$(git -C "$(dirname "$ephemeral_request")/source.git" rev-parse HEAD)" = "$ephemeral"

    # Keep the original direct enqueue and shard-publication coverage isolated
    # from the installed-hook requests above.
    git config --global --unset-all hook.zoekt-context-check.command
    git config --global --unset-all hook.zoekt-context-check.event
    export XDG_STATE_HOME="$TMPDIR/state"
    repository="$TMPDIR/repository"
    mkdir -p "$repository"
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
