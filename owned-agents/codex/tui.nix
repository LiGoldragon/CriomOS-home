{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex";
  text = ''
    arguments=("$@")
    explicit_remote=0
    explicit_cd=0
    explicit_sandbox=0
    explicit_approval=0
    raw_invocation=0
    option_parsing=1
    remote_value_next=0
    invalid_remote=0

    for argument in "''${arguments[@]}"; do
      if [ "$option_parsing" = 0 ]; then
        continue
      fi
      if [ "$remote_value_next" = 1 ]; then
        if [ "$argument" != "unix://" ]; then
          invalid_remote=1
        fi
        remote_value_next=0
        continue
      fi
      case "$argument" in
        --)
          option_parsing=0
          ;;
        --remote)
          explicit_remote=1
          remote_value_next=1
          ;;
        --remote=unix://)
          explicit_remote=1
          ;;
        --remote=*|--remote-auth-token-env|--remote-auth-token-env=*)
          invalid_remote=1
          ;;
        -C|--cd|-C?*|--cd=*)
          explicit_cd=1
          ;;
        -s|--sandbox|-s?*|--sandbox=*)
          explicit_sandbox=1
          ;;
        -a|--ask-for-approval|-a?*|--ask-for-approval=*)
          explicit_approval=1
          ;;
        --version|-V|--help|-h)
          raw_invocation=1
          ;;
      esac
    done

    if [ "$invalid_remote" = 1 ] || [ "$remote_value_next" = 1 ]; then
      printf '%s\n' 'CriomOS codex: normal TUIs attach only to the managed unix:// app-server' >&2
      exit 126
    fi

    if [ "$raw_invocation" = 1 ]; then
      exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
    fi

    remote_tui() {
      remote_arguments=()
      if [ "$explicit_cd" = 0 ]; then
        remote_arguments+=(--cd "$PWD")
      fi
      if [ "$explicit_sandbox" = 0 ]; then
        remote_arguments+=(--sandbox danger-full-access)
      fi
      if [ "$explicit_approval" = 0 ]; then
        remote_arguments+=(--ask-for-approval never)
      fi
      exec ${codexCliPackage}/bin/codex "''${remote_arguments[@]}" "$@"
    }

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --)
          break
          ;;
        --remote|--remote-auth-token-env)
          shift
          [ "$#" -gt 0 ] || break
          shift
          ;;
        --remote=*|--remote-auth-token-env=*)
          shift
          ;;
        -c|--config|--enable|--disable|-i|--image|-m|--model|-p|--profile|-s|--sandbox|-C|--cd|--add-dir|-a|--ask-for-approval|--local-provider)
          shift
          [ "$#" -gt 0 ] || break
          shift
          ;;
        --config=*|--enable=*|--disable=*|--image=*|--model=*|--profile=*|--sandbox=*|--cd=*|--add-dir=*|--ask-for-approval=*|--local-provider=*)
          shift
          ;;
        -*)
          shift
          ;;
        resume|fork)
          if [ "$explicit_remote" = 1 ]; then
            remote_tui "''${arguments[@]}"
          fi
          remote_tui --remote unix:// "''${arguments[@]}"
          ;;
        app-server)
          shift
          case "$1:$2" in
            # `daemon version` is an observational health probe.  Every
            # session-creating, proxying, and schema-writing app-server route
            # remains owned by the persistent codex-remote-control service.
            daemon:version)
              exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
              ;;
            *)
              printf '%s\\n' 'CriomOS codex: app-server lifecycle is owned by codex-remote-control; use direct-codex only for raw recovery' >&2
              exit 126
              ;;
          esac
          ;;
        exec|review|login|logout|mcp|plugin|mcp-server|remote-control|completion|update|doctor|sandbox|apply|queue|archive|delete|migrate-rollouts|unarchive|cloud|features|help)
          exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
          ;;
        *)
          break
          ;;
      esac
    done

    if [ "$explicit_remote" = 1 ]; then
      remote_tui "''${arguments[@]}"
    fi

    remote_tui --remote unix:// "''${arguments[@]}"
  '';
}
