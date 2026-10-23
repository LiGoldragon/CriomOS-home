{ pkgs, inputs, workspaceRoot ? "/home/li/primary", ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = inputs.primary.packages.${system}.curriculum;
  projector = inputs.curriculum-deploy.packages.${system}.default;
  sourceRoot = homeDirectory: "${homeDirectory}/.local/state/curriculum-context";
  environment = homeDirectory: let
    root = sourceRoot homeDirectory;
  in [
    "CURRICULUM_CONTEXT_LAYOUT=2"
    "CURRICULUM_PSYCHES_REPOSITORY_DIR=${root}/psyche-context"
    "CURRICULUM_PSYCHES_REPOSITORY_URL=https://github.com/LiGoldragon/psyche-context.git"
    "CURRICULUM_MIND_CONTEXT_DIR=${root}/mind-context"
    "CURRICULUM_MIND_CONTEXT_URL=https://github.com/LiGoldragon/mind-context.git"
    "CURRICULUM_FIELD_CONTEXT_DIR=${root}/field-context"
    "CURRICULUM_FIELD_CONTEXT_URL=https://github.com/LiGoldragon/field-context.git"
    "CURRICULUM_CONTEXT_REFRESH_PROGRAM=${refresh}/bin/curriculum-refresh-contexts"
    "CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom"
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
  agents = pkgs.writeShellScriptBin "install-curriculum-claude-agents" ''
    set -eu
    directory="$HOME/.claude/agents"
    mkdir -p "$directory"
    for attempt in $(${pkgs.coreutils}/bin/seq 1 1200); do
      [ -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ] && break
      ${pkgs.coreutils}/bin/sleep 0.05
    done
    for role in general-purpose book-author; do
      temporary=$(${pkgs.coreutils}/bin/mktemp "$directory/.$role.XXXXXX")
      if ! ${runtime}/bin/curriculum --claude-agent-markdown \
        "ComposeRole.{ $role ClaudeAgent }" > "$temporary"; then
        ${pkgs.coreutils}/bin/rm -f "$temporary"
        exit 1
      fi
      ${pkgs.coreutils}/bin/mv "$temporary" "$directory/$role.md"
    done
  '';
  projectRoles = pkgs.writeShellApplication {
    name = "project-declared-curriculum-roles";
    text = ''
      socket="''${XDG_RUNTIME_DIR:?}/curriculum/curriculum.sock"
      reply=$(${projector}/bin/curriculum-deploy \
        "ProjectRoles.{ «$socket» «${workspaceRoot}» [ { { general-purpose ClaudeAgent } «.claude/agents/general-purpose.md» } { { book-author ClaudeAgent } «.claude/agents/book-author.md» } ] }")
      test "$reply" = 'RolesProjected.{ 2 }'
      test -r ${workspaceRoot}/.claude/agents/general-purpose.md
      test -r ${workspaceRoot}/.claude/agents/book-author.md
    '';
  };
  makeAwaitReady = name: deadline: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      diagnostic=$(mktemp)
      trap 'rm -f "$diagnostic"' EXIT
      status=0
      # shellcheck disable=SC2016
      timeout --foreground --kill-after=1s ${deadline} \
        ${pkgs.runtimeShell} -c '
          diagnostic="$1"
          main_pid="$2"
          while :; do
            if [ -n "$main_pid" ] && ! kill -0 "$main_pid" 2>/dev/null; then
              echo "curriculum-nexus exited before readiness" >> "$diagnostic"
              exit 1
            fi
            if reply=$(${runtime}/bin/curriculum "ResolveSources.[]" 2>"$diagnostic"); then
              case "$reply" in
                SourcesResolved.*) exit 0 ;;
                *) printf "%s\n" "$reply" > "$diagnostic" ;;
              esac
            fi
            ${pkgs.coreutils}/bin/sleep 0.05
          done
        ' await-declared-curriculum-ready "$diagnostic" "''${1:-}" || status=$?
      if [ "$status" -ne 0 ]; then
        cat "$diagnostic" >&2
        if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
          echo "curriculum-nexus did not answer ResolveSources before the readiness deadline" >&2
        else
          echo "curriculum-nexus readiness probe failed" >&2
        fi
        exit "$status"
      fi
    '';
  };
  awaitReady = makeAwaitReady "await-declared-curriculum-ready" "30s";
  awaitReadyCheck = makeAwaitReady "await-declared-curriculum-ready-check" "0.25s";
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
    ExecStartPost=${awaitReady}/bin/await-declared-curriculum-ready $MAINPID
  '');
  activate = pkgs.writeShellApplication {
    name = "activate-declared-curriculum";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      target="$HOME/.config/systemd/user/curriculum-nexus.service.d"
      mkdir -p "$target"
      temporary=$(mktemp "$target/.50-declared-runtime.conf.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      ln -s ${unit} "$temporary.link"
      mv -T "$temporary.link" "$target/50-declared-runtime.conf"
      rm -f "$temporary"
      trap - EXIT
      systemctl --user daemon-reload
      systemctl --user restart curriculum-nexus.service
      systemctl --user is-active --quiet curriculum-nexus.service
    '';
  };
in
assert inputs.curriculum-source.rev == inputs.primary.inputs.curriculum.rev;
pkgs.runCommand "curriculum-resolver-deployment" {
  passthru = {
    inherit runtime projector environment unit refresh agents projectRoles awaitReady awaitReadyCheck activate;
    inherit (inputs.primary.inputs) psyche-context mind-context field-context;
  };
} ''
  mkdir -p "$out/bin"
  ln -s ${cli}/bin/curriculum "$out/bin/curriculum"
  ln -s ${projectRoles}/bin/project-declared-curriculum-roles "$out/bin/project-declared-curriculum-roles"
  ln -s ${awaitReady}/bin/await-declared-curriculum-ready "$out/bin/await-declared-curriculum-ready"
  ln -s ${activate}/bin/activate-declared-curriculum "$out/bin/activate-declared-curriculum"
''
