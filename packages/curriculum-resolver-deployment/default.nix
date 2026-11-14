{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = inputs.flow-0550.packages.${system}.curriculum;
  sourceRoot = homeDirectory: "${homeDirectory}/.local/state/curriculum-context";
  environment = homeDirectory: let
    root = sourceRoot homeDirectory;
  in [
    "CURRICULUM_CONTEXT_LAYOUT=2"
    "CURRICULUM_PSYCHES_REPOSITORY_DIR=${root}/psyche-belief"
    "CURRICULUM_PSYCHES_REPOSITORY_URL=https://github.com/LiGoldragon/psyche-belief.git"
    "CURRICULUM_MIND_CONTEXT_DIR=${root}/mind-belief"
    "CURRICULUM_MIND_CONTEXT_URL=https://github.com/LiGoldragon/mind-belief.git"
    "CURRICULUM_FIELD_CONTEXT_DIR=${root}/field-belief"
    "CURRICULUM_FIELD_CONTEXT_URL=https://github.com/LiGoldragon/field-belief.git"
    "CURRICULUM_CONTEXT_REFRESH_PROGRAM=${refresh}/bin/curriculum-refresh-contexts"
    "CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom"
    "CURRICULUM_RECORDS_DIR=${homeDirectory}/primary/flows"
  ];
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
      local_revision=$("$git" -C "$directory" rev-parse HEAD)
      remote_revision=$("$git" -C "$directory" \
        rev-parse refs/remotes/origin/main)
      if [ "$local_revision" != "$remote_revision" ]; then
        echo "context checkout is not origin/main: $directory" >&2
        exit 1
      fi
    }
    refresh_repo "$CURRICULUM_PSYCHES_REPOSITORY_DIR" \
      "$CURRICULUM_PSYCHES_REPOSITORY_URL"
    refresh_repo "$CURRICULUM_MIND_CONTEXT_DIR" \
      "$CURRICULUM_MIND_CONTEXT_URL"
    refresh_repo "$CURRICULUM_FIELD_CONTEXT_DIR" \
      "$CURRICULUM_FIELD_CONTEXT_URL"
  '';
  cli = pkgs.writeShellScriptBin "curriculum" ''
    exec ${runtime}/bin/curriculum "$@"
  '';
  unit = pkgs.writeText "curriculum-declared-runtime.conf" (''
    [Service]
    Environment=
    Environment=XDG_RUNTIME_DIR=%t
    Environment=PATH=${pkgs.lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.coreutils ]}
  '' + pkgs.lib.concatMapStringsSep "\n" (value: "Environment=" + value) (environment "%h") + ''

    WorkingDirectory=%h/primary
    ExecStartPre=${refresh}/bin/curriculum-refresh-contexts
    ExecStart=
    ExecStart=${runtime}/bin/curriculum-nexus
    ExecStartPost=
  '');
in
assert inputs.curriculum-source.rev == inputs.flow-0550.inputs.curriculum.rev;
pkgs.runCommand "curriculum-resolver-deployment" {
  passthru = {
    inherit runtime environment unit refresh;
    inherit (inputs.primary.inputs) psyche-belief mind-belief field-belief;
  };
} ''
  mkdir -p "$out/bin"
  ln -s ${cli}/bin/curriculum "$out/bin/curriculum"
''
