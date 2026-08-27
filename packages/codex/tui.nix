{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex";
  text = ''
    arguments=("$@")
    explicit_remote=0
    explicit_cd=0
    raw_invocation=0
    option_parsing=1

    for argument in "''${arguments[@]}"; do
      if [ "$option_parsing" = 0 ]; then
        continue
      fi
      case "$argument" in
        --)
          option_parsing=0
          ;;
        --remote|--remote=*)
          explicit_remote=1
          ;;
        -C|--cd|-C?*|--cd=*)
          explicit_cd=1
          ;;
        --version|-V|--help|-h)
          raw_invocation=1
          ;;
      esac
    done

    if [ "$raw_invocation" = 1 ]; then
      exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
    fi

    remote_tui() {
      if [ "$explicit_cd" = 1 ]; then
        exec ${codexCliPackage}/bin/codex "$@"
      fi
      exec ${codexCliPackage}/bin/codex --cd "$PWD" "$@"
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
        exec|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|doctor|sandbox|apply|queue|archive|delete|migrate-rollouts|unarchive|cloud|features|help)
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
