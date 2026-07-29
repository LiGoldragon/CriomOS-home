{
  pkgs,
  curl ? pkgs.curl,
  gopass ? pkgs.gopass,
  coreutils ? pkgs.coreutils,
  gnugrep ? pkgs.gnugrep,
}:
pkgs.writeShellApplication {
  name = "dolthub-create-database";
  runtimeInputs = [
    curl
    gopass
    coreutils
    gnugrep
  ];
  text = ''
    set -o pipefail

    usage() {
      printf '%s\n' \
        "Usage: dolthub-create-database --owner OWNER --database NAME --visibility public|private [--gopass-entry PATH]" \
        "Create the hosted DoltHub database OWNER/NAME if it is missing." \
        "The default GoPass entry is dolthub.com/api-token."
    }

    usage_error() {
      printf 'dolthub-create-database: %s\n' "$1" >&2
      usage >&2
      exit 2
    }

    valid_name() {
      case "$1" in
        ""|*[!A-Za-z0-9._-]*) return 1 ;;
        *) return 0 ;;
      esac
    }

    owner=""
    database=""
    visibility=""
    gopass_entry="dolthub.com/api-token"

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --owner)
          [ "$#" -ge 2 ] || usage_error "--owner needs a value"
          owner="$2"
          shift 2
          ;;
        --database)
          [ "$#" -ge 2 ] || usage_error "--database needs a value"
          database="$2"
          shift 2
          ;;
        --visibility)
          [ "$#" -ge 2 ] || usage_error "--visibility needs a value"
          visibility="$2"
          shift 2
          ;;
        --gopass-entry)
          [ "$#" -ge 2 ] || usage_error "--gopass-entry needs a value"
          gopass_entry="$2"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          usage_error "unknown argument: $1"
          ;;
      esac
    done

    [ -n "$owner" ] || usage_error "--owner is required"
    [ -n "$database" ] || usage_error "--database is required"
    [ -n "$visibility" ] || usage_error "--visibility is required"
    valid_name "$owner" || usage_error "owner must contain only letters, digits, dot, underscore, or hyphen"
    valid_name "$database" || usage_error "database must contain only letters, digits, dot, underscore, or hyphen"

    case "$visibility" in
      public|private) ;;
      *) usage_error "visibility must be public or private" ;;
    esac

    response_body="$(mktemp)"
    status_file="$(mktemp)"
    trap 'rm -f "$response_body" "$status_file"' EXIT HUP INT TERM

    status=""
    set +e
    gopass show -o "$gopass_entry" 2>/dev/null \
      | curl --silent --request POST \
        --header 'Content-Type: application/json' \
        --data-binary "{\"ownerName\":\"$owner\",\"repoName\":\"$database\",\"visibility\":\"$visibility\"}" \
        --variable token@- \
        --expand-header 'Authorization: token {{token:trim}}' \
        --output "$response_body" \
        --write-out '%{http_code}\n' \
        https://www.dolthub.com/api/v1alpha1/database > "$status_file"
    pipeline_status=("''${PIPESTATUS[@]}")
    set -e
    status="$(< "$status_file")"

    gopass_status="''${pipeline_status[0]}"
    curl_status="''${pipeline_status[1]}"
    if [ "$gopass_status" -ne 0 ]; then
      printf 'dolthub-create-database: could not read GoPass entry %s\n' "$gopass_entry" >&2
      exit 1
    fi

    if [ "$curl_status" -eq 0 ] && [[ "$status" == 2?? ]]; then
      printf 'created DoltHub database %s/%s (%s)\n' "$owner" "$database" "$visibility"
      exit 0
    fi

    if [ "$curl_status" -eq 0 ] \
      && [ "$status" = 409 ] \
      && grep -Fq -- "$owner" "$response_body" \
      && grep -Fq -- "$database" "$response_body" \
      && grep -Eqi -- 'already[[:space:]]+exists' "$response_body"; then
      printf 'DoltHub database %s/%s already exists (%s)\n' "$owner" "$database" "$visibility"
      exit 0
    fi

    if [ "$status" = 409 ]; then
      printf 'dolthub-create-database: DoltHub conflict did not confirm that %s/%s already exists\n' "$owner" "$database" >&2
      exit 1
    fi

    printf 'dolthub-create-database: DoltHub request failed (HTTP %s)\n' "''${status:-unknown}" >&2
    exit 1
  '';
}
