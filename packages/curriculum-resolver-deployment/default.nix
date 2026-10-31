{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = inputs.primary.packages.${system}.curriculum;
  sourceRoot = homeDirectory: "${homeDirectory}/.local/state/curriculum-context";
  refresh = pkgs.writeShellScriptBin "curriculum-refresh-contexts" ''
    set -eu
    git=${pkgs.git}/bin/git
    refresh_repo() {
      directory="$1"
      url="$2"
      if [ -d "$directory/.git" ]; then
        actual_url=$("$git" -C "$directory" config --get remote.origin.url)
        if [ "$actual_url" != "$url" ]; then
          echo "unexpected context origin for $directory" >&2
          exit 1
        fi
        if [ -n "$("$git" -C "$directory" status --porcelain)" ]; then
          echo "refusing to discard local context changes in $directory" >&2
          exit 1
        fi
        "$git" -C "$directory" fetch --quiet --no-tags --prune origin \
          +refs/heads/main:refs/remotes/origin/main
        "$git" -C "$directory" checkout --quiet --force --detach \
          refs/remotes/origin/main
      else
        if [ -e "$directory" ] || [ -L "$directory" ]; then
          echo "context path is not a managed checkout: $directory" >&2
          exit 1
        fi
        mkdir -p "$(dirname "$directory")"
        "$git" clone --quiet --depth 1 --single-branch \
          --branch main "$url" "$directory"
      fi
    }
    refresh_repo "$CURRICULUM_PSYCHES_REPOSITORY_DIR" \
      "$CURRICULUM_PSYCHES_REPOSITORY_URL"
    refresh_repo "$CURRICULUM_MIND_CONTEXT_DIR" \
      "$CURRICULUM_MIND_CONTEXT_URL"
    refresh_repo "$CURRICULUM_FIELD_CONTEXT_DIR" \
      "$CURRICULUM_FIELD_CONTEXT_URL"
  '';
  environment =
    homeDirectory: rolesFile: recordsDirectory:
    let
      root = sourceRoot homeDirectory;
    in
    [
      "CURRICULUM_CONTEXT_LAYOUT=2"
      "CURRICULUM_PSYCHES_REPOSITORY_DIR=${root}/psyche-context"
      "CURRICULUM_PSYCHES_REPOSITORY_URL=https://github.com/LiGoldragon/psyche-context.git"
      "CURRICULUM_MIND_CONTEXT_DIR=${root}/mind-context"
      "CURRICULUM_MIND_CONTEXT_URL=https://github.com/LiGoldragon/mind-context.git"
      "CURRICULUM_FIELD_CONTEXT_DIR=${root}/field-context"
      "CURRICULUM_FIELD_CONTEXT_URL=https://github.com/LiGoldragon/field-context.git"
      "CURRICULUM_CONTEXT_REFRESH_PROGRAM=${refresh}/bin/curriculum-refresh-contexts"
      "CURRICULUM_ROLES_FILE=${rolesFile}"
      "CURRICULUM_RECORDS_DIR=${recordsDirectory}"
    ];
  cli = pkgs.writeShellScriptBin "curriculum" ''
    exec ${runtime}/bin/curriculum "$@"
  '';
in
assert inputs.curriculum-source.rev == inputs.primary.inputs.curriculum.rev;
pkgs.runCommand "curriculum-resolver-deployment"
  {
    passthru = {
      inherit runtime environment refresh;
      inherit (inputs.primary.inputs) psyche-context mind-context field-context;
    };
  }
  ''
    mkdir -p "$out/bin"
    ln -s ${cli}/bin/curriculum "$out/bin/curriculum"
  ''
