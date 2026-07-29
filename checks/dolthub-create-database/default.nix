{ pkgs, ... }:
let
  command = pkgs.callPackage ../../packages/dolthub-create-database { };
  fakeGopass = pkgs.writeShellScriptBin "gopass" ''
    set -eu
    test "$#" -eq 3
    test "$1" = show
    test "$2" = -o
    test "$3" = dolthub.com/api-token
    printf '%s\n' mock-token
  '';
  fakeCurl = pkgs.writeShellScriptBin "curl" ''
    set -eu

    output=""
    request_data=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --silent|--request)
          shift
          [ "$#" -gt 0 ] && [ "$1" = POST ] && shift || true
          ;;
        --header)
          test "$2" = 'Content-Type: application/json'
          shift 2
          ;;
        --data-binary)
          request_data="$2"
          shift 2
          ;;
        --variable)
          test "$2" = token@-
          IFS= read -r token
          test "$token" = mock-token
          shift 2
          ;;
        --expand-header)
          test "$2" = 'Authorization: token {{token:trim}}'
          shift 2
          ;;
        --output)
          output="$2"
          shift 2
          ;;
        --write-out)
          test "$2" = '%{http_code}\n'
          shift 2
          ;;
        https://www.dolthub.com/api/v1alpha1/database)
          shift
          ;;
        *)
          echo "unexpected curl argument: $1" >&2
          exit 1
          ;;
      esac
    done

    test -n "$output"
    case "$request_data" in
      *'"repoName":"already"'*)
        printf '%s' '{"message":"database owner/already already exists"}' > "$output"
        ;;
      *)
        printf '%s' '{"message":"database owner/somewhere-else already exists"}' > "$output"
        ;;
    esac
    printf '409\n'
  '';
  mockedCommand = pkgs.callPackage ../../packages/dolthub-create-database {
    curl = fakeCurl;
    gopass = fakeGopass;
  };
in
pkgs.runCommand "dolthub-create-database-check"
  {
    nativeBuildInputs = [
      command
      mockedCommand
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    dolthub-create-database --help | grep -F -- '--owner OWNER'
    dolthub-create-database --help | grep -F -- '--gopass-entry PATH'

    if dolthub-create-database --owner 'bad/name' --database beads --visibility private; then
      echo 'invalid owner unexpectedly passed validation' >&2
      exit 1
    fi

    if dolthub-create-database --owner owner --database beads --visibility shared; then
      echo 'invalid visibility unexpectedly passed validation' >&2
      exit 1
    fi

    dolthub-create-database --help | grep -F -- '--visibility public|private'
    ${mockedCommand}/bin/dolthub-create-database --owner owner --database already --visibility private \
      | grep -F -- 'DoltHub database owner/already already exists (private)'
    if ${mockedCommand}/bin/dolthub-create-database --owner owner --database elsewhere --visibility private >/dev/null 2>&1; then
      echo 'unverified 409 unexpectedly passed' >&2
      exit 1
    fi

    grep -F -- '--variable token@-' "${command}/bin/dolthub-create-database"
    grep -F -- 'Authorization: token {{token:trim}}' "${command}/bin/dolthub-create-database"
    grep -F -- 'https://www.dolthub.com/api/v1alpha1/database' "${command}/bin/dolthub-create-database"
    grep -F -- 'already[[:space:]]+exists' "${command}/bin/dolthub-create-database"
    if grep -F -- 'Bearer' "${command}/bin/dolthub-create-database"; then
      echo 'Bearer authentication must not be present' >&2
      exit 1
    fi

    touch "$out"
  ''
