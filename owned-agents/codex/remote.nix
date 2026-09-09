{
  pkgs,
  codexCliPackage,
  ghostty ? pkgs.ghostty,
  systemctl ? pkgs.systemd,
  systemdRun ? pkgs.systemd,
}:
let
  codexRemote = pkgs.writeShellApplication {
    name = "codex-remote";
    text = ''
      exec ${codexCliPackage}/bin/codex --remote unix:// "$@"
    '';
  };
  codexDesktop = pkgs.writeShellApplication {
    name = "codex-desktop";
    text = ''
      service=codex-remote-control.service

      usage() {
        cat >&2 <<'USAGE'
      usage:
        codex-desktop fresh PROMPT_FILE WORKING_DIRECTORY
        codex-desktop resume THREAD_UUID WORKING_DIRECTORY
        codex-desktop status
        codex-desktop restart-service
      USAGE
        exit 2
      }

      require_service() {
        if ! ${systemctl}/bin/systemctl --user is-active --quiet "$service"; then
          echo "$service is not active" >&2
          echo "use 'codex-desktop restart-service' to restart its Nix-owned unit" >&2
          exit 3
        fi
      }

      launch() {
        title=$1
        working_directory=$2
        shift 2
        require_service
        exec ${systemdRun}/bin/systemd-run \
          --user --scope --collect --quiet \
          --property=CPUWeight=1000 \
          --property=IOWeight=1000 \
          --property=MemoryAccounting=yes \
          --property=MemoryLow=512M \
          --property=OOMPolicy=continue \
          ${ghostty}/bin/ghostty \
          --gtk-single-instance=false \
          --class=criomos-codex-desktop \
          --title="$title" \
          --working-directory="$working_directory" \
          --wait-after-command \
          -e ${codexRemote}/bin/codex-remote --cd "$working_directory" "$@"
      }

      case "''${1:-}" in
        fresh)
          [ "$#" -eq 3 ] || usage
          prompt_file=$2
          working_directory=$3
          [ -r "$prompt_file" ] || { echo "prompt file is not readable: $prompt_file" >&2; exit 2; }
          [ -d "$working_directory" ] || { echo "working directory is not a directory: $working_directory" >&2; exit 2; }
          prompt=$(<"$prompt_file")
          [ -n "$prompt" ] || { echo "prompt file is empty: $prompt_file" >&2; exit 2; }
          launch "Codex fresh" "$working_directory" --model gpt-6-astra "$prompt"
          ;;
        resume)
          [ "$#" -eq 3 ] || usage
          thread_id=$2
          working_directory=$3
          if ! [[ "$thread_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
            echo "resume requires an exact Codex thread UUID" >&2
            exit 2
          fi
          [ -d "$working_directory" ] || { echo "working directory is not a directory: $working_directory" >&2; exit 2; }
          launch "Codex resume $thread_id" "$working_directory" resume "$thread_id"
          ;;
        status)
          [ "$#" -eq 1 ] || usage
          exec ${systemctl}/bin/systemctl --user status --no-pager "$service"
          ;;
        restart-service)
          [ "$#" -eq 1 ] || usage
          ${systemctl}/bin/systemctl --user restart "$service"
          exec ${systemctl}/bin/systemctl --user status --no-pager "$service"
          ;;
        *) usage ;;
      esac
    '';
  };
in
pkgs.symlinkJoin {
  name = "codex-remote-tools";
  paths = [
    codexRemote
    codexDesktop
  ];
  passthru = { inherit codexRemote codexDesktop; };
}
