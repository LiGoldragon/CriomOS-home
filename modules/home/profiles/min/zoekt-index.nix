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
      if [ "$#" -ne 1 ]; then
        echo "usage: zoekt-index-snapshot WORK_DIRECTORY" >&2
        exit 2
      fi
      work_directory=$1
      request="$work_directory/request.json"
      source_repository="$work_directory/source.git"
      index_directory="$work_directory/index"
      revision=$(jq -er .revision "$request")
      test "$(git -C "$source_repository" rev-parse HEAD)" = "$revision"
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
      if [ "$#" -lt 1 ]; then
        echo "usage: zoekt-index-offload enqueue REPOSITORY | drain" >&2
        exit 2
      fi
      state_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/zoekt-index"
      queue_directory="$state_directory/requests"
      mkdir -p "$queue_directory"

      enqueue() {
        if [ "$#" -ne 1 ]; then
          echo "usage: zoekt-index-offload enqueue REPOSITORY" >&2
          exit 2
        fi
        repository=$(git -C "$1" rev-parse --show-toplevel)
        revision=$(git -C "$repository" rev-parse --verify HEAD)
        identity=$(git -C "$repository" remote get-url origin 2>/dev/null || printf '%s' "$repository")
        repository_key=$(printf '%s' "$identity" | sha256sum | cut -d ' ' -f 1)
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
        temporary=$(mktemp "$queue_directory/.request.XXXXXX")
        trap 'rm -f "$temporary"' EXIT
        jq -n \
          --arg repository "$repository" \
          --arg repositoryIdentity "$identity" \
          --arg repositoryKey "$repository_key" \
          --arg revision "$revision" \
          --argjson sequence "$sequence" \
          '{repository: $repository, repositoryIdentity: $repositoryIdentity, repositoryKey: $repositoryKey, revision: $revision, sequence: $sequence}' \
          > "$temporary"
        mv "$temporary" "$queue_directory/$sequence_name-$repository_key-$revision.json"
        trap - EXIT
      }

      install_generation() {
        repository_key=$1
        result_directory=$2
        data_directory="''${XDG_DATA_HOME:-$HOME/.local/share}/zoekt"
        index_path="$data_directory/index"
        generations="$data_directory/index-generations"
        current="$data_directory/index-current"
        mkdir -p "$data_directory" "$generations" || return

        if [ ! -L "$index_path" ]; then
          imported="$generations/imported"
          rm -rf "$imported" || return
          if [ -d "$index_path" ]; then
            mv "$index_path" "$imported" || return
          else
            mkdir "$imported" || return
          fi
          mkdir -p "$imported/.manifests" || return
          rm -f "$current.new" || return
          ln -s "$imported" "$current.new" || return
          mv -T "$current.new" "$current" || return
          ln -s "$current" "$index_path" || return
        fi

        previous=$(readlink -f "$current") || return
        generation=$(mktemp -d "$generations/.generation.XXXXXX") || return
        cp -al "$previous/." "$generation/" || return
        mkdir -p "$generation/.manifests" || return
        manifest="$generation/.manifests/$repository_key"
        if [ -f "$manifest" ]; then
          while IFS= read -r old_shard; do
            rm -f -- "$generation/$old_shard" || return
          done < "$manifest"
        fi
        rm -f "$manifest" || return
        : > "$manifest" || return
        for new_shard in "$result_directory"/*.zoekt; do
          rm -f -- "$generation/$(basename "$new_shard")" || return
          shard_name="$repository_key-$(basename "$new_shard")"
          cp "$new_shard" "$generation/$shard_name" || return
          printf '%s\n' "$shard_name" >> "$manifest" || return
        done
        final_generation="$generations/$(basename "$generation" | sed 's/^\.//')"
        mv "$generation" "$final_generation" || return
        rm -f "$current.new" || return
        ln -s "$final_generation" "$current.new" || return
        mv -T "$current.new" "$current" || return
      }

      process_request() {
        request=$1
        index_host=${lib.escapeShellArg cfg.indexingHost}
        repository=$(jq -er .repository "$request") || return
        identity=$(jq -er .repositoryIdentity "$request") || return
        repository_key=$(jq -er .repositoryKey "$request") || return
        revision=$(jq -er .revision "$request") || return
        git -C "$repository" cat-file -e "$revision^{commit}" || return

        local_work=$(mktemp -d "$state_directory/.work.XXXXXX") || return
        mkdir -p "$local_work/result" || return
        cp "$request" "$local_work/request.json" || return
        git init --bare --quiet "$local_work/source.git" || return
        git -C "$local_work/source.git" fetch --quiet --depth=1 "$repository" \
          "$revision:refs/heads/snapshot" || return
        git -C "$local_work/source.git" symbolic-ref HEAD refs/heads/snapshot || return
        git -C "$local_work/source.git" remote add origin "$identity" || return
        test "$(git -C "$local_work/source.git" rev-parse HEAD)" = "$revision" || return

        nix copy --to "ssh://$index_host" ${remoteIndexer} || return
        remote_work=$(ssh -n "$index_host" 'mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/zoekt-index.XXXXXX"') || return
        rsync -a -- "$local_work/request.json" "$local_work/source.git" "$index_host:$remote_work/" || return
        ssh -n "$index_host" ${remoteIndexer}/bin/zoekt-index-snapshot "$remote_work" || return
        rsync -a -- "$index_host:$remote_work/index/" "$local_work/result/" || return
        find "$local_work/result" -maxdepth 1 -type f -name '*.zoekt' -print -quit | grep -q . || return

        install_generation "$repository_key" "$local_work/result" || return
        rm -f -- "$request"
        rm -rf "$local_work"
        ssh -n "$index_host" rm -rf -- "$remote_work" >/dev/null 2>&1 || true
      }

      drain_once() {
        requests=("$queue_directory"/*.json)
        [ -e "''${requests[0]}" ] || return 0
        for request in "''${requests[@]}"; do
          process_request "$request" || return 1
        done
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
        *)
          echo "usage: zoekt-index-offload enqueue REPOSITORY | drain" >&2
          exit 2
          ;;
      esac
    '';
  };

  enqueue = pkgs.writeShellApplication {
    name = "zoekt-index-repository";
    runtimeInputs = [ offload ];
    text = ''
      exec zoekt-index-offload enqueue "$@"
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
