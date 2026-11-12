{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  cfg = config.criomosHome.zoektIndex;
  gitRepositoryContext = ''
    git_without_repository_context() (
      while IFS= read -r variable; do
        unset "$variable"
      done < <(git rev-parse --local-env-vars)
      unset GIT_NAMESPACE
      command git "$@"
    )

    git_in_repository() (
      repository=$1
      shift
      git_without_repository_context -C "$repository" "$@"
    )
  '';

  # This exact derivation is copied to the indexing host. Both ends therefore
  # use the package set selected by this Home generation.
  remoteIndexer = pkgs.writeShellApplication {
    name = "zoekt-index-snapshot";
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.zoekt
    ];
    text = ''
      ${gitRepositoryContext}

      if [ "$#" -ne 1 ]; then
        echo "usage: zoekt-index-snapshot WORK_DIRECTORY" >&2
        exit 2
      fi
      work_directory=$1
      request="$work_directory/request.json"
      source_repository="$work_directory/source.git"
      index_directory="$work_directory/index"
      revision=$(jq -er .revision "$request")
      test "$(git_in_repository "$source_repository" rev-parse HEAD)" = "$revision"
      mkdir -p "$index_directory"
      zoekt-git-index -index "$index_directory" -branches HEAD "$source_repository"
    '';
  };

  offload = pkgs.writeShellApplication {
    name = "zoekt-index-offload";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
      pkgs.gnugrep
      pkgs.jq
      pkgs.nix
      pkgs.openssh
      pkgs.rsync
      pkgs.gnused
      pkgs.systemd
      pkgs.gnutar
      pkgs.inotify-tools
      pkgs.util-linux
    ];
    text = ''
      ${gitRepositoryContext}

      if [ "$#" -lt 1 ]; then
        echo "usage: zoekt-index-offload enqueue REPOSITORY | drain | install-shards RESULT_DIRECTORY" >&2
        exit 2
      fi
      state_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/zoekt-index"
      queue_directory="$state_directory/requests"
      mkdir -p "$queue_directory"

      enqueue() (
        if [ "$#" -ne 1 ]; then
          echo "usage: zoekt-index-offload enqueue REPOSITORY" >&2
          exit 2
        fi
        repository=$(git_in_repository "$1" rev-parse --show-toplevel)
        revision=$(git_in_repository "$repository" rev-parse --verify HEAD)
        identity=$(git_in_repository "$repository" remote get-url origin 2>/dev/null || printf '%s' "$repository")
        repository_key=$(printf '%s' "$identity" | sha256sum | cut -d ' ' -f 1)
        machine_identity=$(cat ${lib.escapeShellArg cfg.machineIdentityFile})
        numeric_user_identity=$(id -u)
        exec 8>"$state_directory/enqueue.lock"
        flock 8
        sequence_file="$state_directory/next-sequence"
        sequence=0
        if [ -f "$sequence_file" ]; then
          sequence=$(cat "$sequence_file")
        fi
        sequence=$((sequence + 1))
        sequence_temporary=$(mktemp "$state_directory/.sequence.XXXXXX")
        printf '%s\n' "$sequence" > "$sequence_temporary"
        mv "$sequence_temporary" "$sequence_file"
        sequence_name=$(printf '%020d' "$sequence")
        remote_work_key=$(printf '%s\0%s\0%s\0%s\0%s' \
          "$machine_identity" "$numeric_user_identity" "$sequence" "$repository_key" "$revision" \
          | sha256sum | cut -d ' ' -f 1)
        indexing_host=${lib.escapeShellArg cfg.indexingHost}
        remote_work_root=${lib.escapeShellArg cfg.remoteWorkRoot}
        remote_work_path="$remote_work_root/$remote_work_key"
        temporary=$(mktemp -d "$queue_directory/.request.XXXXXX")
        trap 'rm -rf "$temporary"' EXIT
        git_without_repository_context init --bare --quiet "$temporary/source.git"
        git_in_repository "$temporary/source.git" fetch --quiet --depth=1 "$repository" \
          "$revision:refs/heads/snapshot"
        git_in_repository "$temporary/source.git" symbolic-ref HEAD refs/heads/snapshot
        git_in_repository "$temporary/source.git" remote add origin "$identity"
        test "$(git_in_repository "$temporary/source.git" rev-parse HEAD)" = "$revision"
        jq -n \
          --arg repository "$repository" \
          --arg repositoryIdentity "$identity" \
          --arg repositoryKey "$repository_key" \
          --arg revision "$revision" \
          --arg indexingHost "$indexing_host" \
          --arg remoteWorkKey "$remote_work_key" \
          --arg remoteWorkRoot "$remote_work_root" \
          --arg remoteWorkPath "$remote_work_path" \
          --argjson sequence "$sequence" \
          '{repository: $repository, repositoryIdentity: $repositoryIdentity, repositoryKey: $repositoryKey, revision: $revision, sequence: $sequence, indexingHost: $indexingHost, remoteWorkKey: $remoteWorkKey, remoteWorkRoot: $remoteWorkRoot, remoteWorkPath: $remoteWorkPath}' \
          > "$temporary/request.json"
        mv "$temporary" "$queue_directory/$sequence_name-$repository_key-$revision"
        trap - EXIT
      )

      install_shards() (
        result_directory=$1
        data_directory="''${XDG_DATA_HOME:-$HOME/.local/share}/zoekt"
        index_path="$data_directory/index"
        mkdir -p "$index_path"
        test ! -L "$index_path"
        incoming=$(mktemp -d "$data_directory/.index-incoming.XXXXXX")
        trap 'rm -rf "$incoming"' EXIT
        new_names="$incoming/new-names"
        : > "$new_names"
        native_family=
        for new_shard in "$result_directory"/*.zoekt; do
          test -f "$new_shard"
          shard_name=$(basename "$new_shard")
          shard_family=$(printf '%s\n' "$shard_name" | sed -n 's/_v[0-9][0-9]*\.[0-9][0-9]*\.zoekt$//p')
          test -n "$shard_family"
          if [ -z "$native_family" ]; then
            native_family=$shard_family
          else
            test "$shard_family" = "$native_family"
          fi
          cp "$new_shard" "$incoming/$shard_name"
          printf '%s\n' "$shard_name" >> "$new_names"
        done
        test -n "$native_family"

        # Zoekt itself publishes each completed artifact with rename and then
        # unlinks stale members of the same native repository-name family.
        while IFS= read -r shard_name; do
          mv -T "$incoming/$shard_name" "$index_path/$shard_name"
        done < "$new_names"
        for existing_shard in "$index_path"/*.zoekt; do
          test -f "$existing_shard" || continue
          existing_name=$(basename "$existing_shard")
          existing_family=$(printf '%s\n' "$existing_name" | sed -n 's/_v[0-9][0-9]*\.[0-9][0-9]*\.zoekt$//p')
          if [ "$existing_family" = "$native_family" ] && ! grep -Fxq "$existing_name" "$new_names"; then
            rm -f -- "$existing_shard"
          fi
        done
      )

      process_request() (
        request_directory=$1
        request="$request_directory/request.json"
        source_repository="$request_directory/source.git"
        index_host=$(jq -er .indexingHost "$request") || return
        remote_work_key=$(jq -er .remoteWorkKey "$request") || return
        remote_work_root=$(jq -er .remoteWorkRoot "$request") || return
        remote_work=$(jq -er .remoteWorkPath "$request") || return
        test "$(printf '%s' "$remote_work_key" | sed -n '/^[0-9a-f]\{64\}$/p')" = "$remote_work_key" || return
        test "$(printf '%s' "$remote_work_root" | sed -n '/^\/[A-Za-z0-9._\/-]*$/p')" = "$remote_work_root" || return
        test "$remote_work" = "$remote_work_root/$remote_work_key" || return
        revision=$(jq -er .revision "$request") || return
        test "$(git_in_repository "$source_repository" rev-parse HEAD)" = "$revision" || return

        connection_timeout=${toString cfg.connectionTimeoutSeconds}
        operation_timeout=${toString cfg.operationTimeoutSeconds}
        ssh_options=(-o BatchMode=yes -o "ConnectTimeout=$connection_timeout")
        nix_ssh_options="-o BatchMode=yes -o ConnectTimeout=$connection_timeout"
        remote_shell="ssh $nix_ssh_options"
        bounded() {
          timeout --foreground --signal=TERM "''${operation_timeout}s" "$@"
        }

        local_work=$(mktemp -d "$state_directory/.work.XXXXXX") || return
        # shellcheck disable=SC2329 # invoked by the EXIT/INT/TERM trap
        cleanup() {
          rm -rf "$local_work"
          if [ -n "''${remote_cleanup_needed:-}" ]; then
            bounded ssh -n "''${ssh_options[@]}" "$index_host" rm -rf -- "$remote_work" >/dev/null 2>&1 || true
          fi
        }
        trap cleanup EXIT INT TERM
        mkdir -p "$local_work/result"

        # The request owns one deterministic remote directory. Reclaiming it
        # is the first remote action of every attempt, so a transport loss or
        # process death leaves work that the same retained request will find.
        bounded ssh -n "''${ssh_options[@]}" "$index_host" \
          "mkdir -p -- $(dirname "$remote_work") && rm -rf -- $remote_work && mkdir -- $remote_work" || return
        remote_cleanup_needed=1
        NIX_SSHOPTS="$nix_ssh_options" bounded nix copy --to "ssh://$index_host" ${remoteIndexer} || return
        bounded rsync --timeout="$operation_timeout" -a -e "$remote_shell" -- \
          "$request" "$source_repository" "$index_host:$remote_work/" || return
        bounded ssh -n "''${ssh_options[@]}" "$index_host" ${remoteIndexer}/bin/zoekt-index-snapshot "$remote_work" || return
        bounded rsync --timeout="$operation_timeout" -a -e "$remote_shell" -- \
          "$index_host:$remote_work/index/" "$local_work/result/" || return
        find "$local_work/result" -maxdepth 1 -type f -name '*.zoekt' -print -quit | grep -q . || return

        install_shards "$local_work/result" || return
        bounded ssh -n "''${ssh_options[@]}" "$index_host" rm -rf -- "$remote_work" || return
        remote_cleanup_needed=
        rm -rf -- "$request_directory"
      )

      drain_once() {
        while IFS= read -r -d "" request; do
          process_request "$request" || return 1
        done < <(find "$queue_directory" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 | sort -z)
      }

      drain() {
        runtime_directory="''${XDG_RUNTIME_DIR:-/tmp}/zoekt-index"
        event_file="$runtime_directory/network-event"
        event_pipe="$runtime_directory/events"
        lock_file="$runtime_directory/drain.lock"
        mkdir -p "$runtime_directory"
        touch "$event_file"
        exec 9>"$lock_file"
        flock -n 9 || exit 0
        rm -f "$event_pipe"
        mkfifo "$event_pipe"
        inotifywait -m -q -e moved_to,close_write --format event \
          "$queue_directory" "$event_file" > "$event_pipe" &
        watcher=$!
        exec 7<"$event_pipe"
        trap 'kill "$watcher" 2>/dev/null || true; rm -f "$event_pipe"' EXIT

        while true; do
          drain_once || true
          IFS= read -r _ <&7 || exit 1
        done
      }

      case "$1" in
        enqueue)
          shift
          enqueue "$@"
          ;;
        drain)
          shift
          [ "$#" -eq 0 ] || { echo "usage: zoekt-index-offload drain" >&2; exit 2; }
          drain
          ;;
        install-shards)
          shift
          [ "$#" -eq 1 ] || { echo "usage: zoekt-index-offload install-shards RESULT_DIRECTORY" >&2; exit 2; }
          install_shards "$@"
          ;;
        *)
          echo "usage: zoekt-index-offload enqueue REPOSITORY | drain | install-shards RESULT_DIRECTORY" >&2
          exit 2
          ;;
      esac
    '';
  };

  enqueue = pkgs.writeShellApplication {
    name = "zoekt-index-repository";
    runtimeInputs = [ offload ];
    text = ''
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        echo "ZoektHook.InvalidRepository" >&2
        exit 2
      fi
      repository=$1
      shift
      case "$#" in
        0) ;;
        1)
          case "$1" in
            0|1) ;;
            *) echo "ZoektHook.InvalidMergePayload" >&2; exit 2 ;;
          esac
          ;;
        *) echo "ZoektHook.InvalidArity" >&2; exit 2 ;;
      esac
      exec zoekt-index-offload enqueue "$repository"
    '';
  };
  networkEvent = pkgs.writeShellApplication {
    name = "zoekt-index-network-event";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      runtime_directory="''${XDG_RUNTIME_DIR:-/tmp}/zoekt-index"
      mkdir -p "$runtime_directory"
      printf 'network\n' > "$runtime_directory/network-event"
    '';
  };
in
{
  options.criomosHome.zoektIndex.indexingHost = lib.mkOption {
    type = lib.types.str;
    default = "prometheus";
    description = "SSH host that turns immutable repository snapshots into local zoekt shards.";
  };
  options.criomosHome.zoektIndex.connectionTimeoutSeconds = lib.mkOption {
    type = lib.types.ints.positive;
    default = 10;
    description = "Maximum time to establish each SSH connection to the indexing host.";
  };
  options.criomosHome.zoektIndex.operationTimeoutSeconds = lib.mkOption {
    type = lib.types.ints.positive;
    default = 300;
    description = "Maximum time for each remote indexing transport operation.";
  };
  options.criomosHome.zoektIndex.remoteWorkRoot = lib.mkOption {
    type = lib.types.strMatching "^/[A-Za-z0-9._/-]+$";
    default = "/tmp/zoekt-index-${config.home.username}";
    description = "Absolute directory on the indexing host that holds request-owned temporary work.";
  };
  options.criomosHome.zoektIndex.machineIdentityFile = lib.mkOption {
    type = lib.types.str;
    default = "/etc/machine-id";
    description = "File containing the stable local machine identity used to own remote work.";
  };

  config = lib.mkIf (sizeAtLeast "Min") {
    home.packages = [
      pkgs.zoekt
      enqueue
      offload
    ];

    systemd.user.services.zoekt-index-drain = {
      Unit.Description = "Build retained zoekt index requests on ${cfg.indexingHost}";
      Service = {
        Type = "simple";
        ExecStart = "${offload}/bin/zoekt-index-offload drain";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "default.target" ];
    };

    # This starts the durable event consumer if a commit predates its session.
    # Once running, inotify delivers every queue event without a timer.
    systemd.user.paths.zoekt-index-drain = {
      Unit.Description = "Notice retained zoekt index requests";
      Path.PathChanged = "%h/.local/state/zoekt-index/requests";
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.zoekt-index-network-event = {
      Unit.Description = "Announce a network-up event to zoekt indexing";
      Service = {
        Type = "oneshot";
        ExecStart = "${networkEvent}/bin/zoekt-index-network-event";
      };
    };

    programs.git.settings.hook.zoekt-index = {
      command = "${enqueue}/bin/zoekt-index-repository .";
      event = [
        "post-commit"
        "post-merge"
      ];
    };
  };
}
