{ pkgs, codexCliPackage }:
pkgs.writeShellApplication {
  name = "codex";
  text = ''
    arguments=("$@")
    explicit_remote=0

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --)
          break
          ;;
        --remote|--remote-auth-token-env)
          explicit_remote=1
          shift
          [ "$#" -gt 0 ] || break
          shift
          ;;
        --remote=*|--remote-auth-token-env=*)
          explicit_remote=1
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
        -* )
          shift
          ;;
        resume|fork)
          exec ${codexCliPackage}/bin/codex --remote unix:// "''${arguments[@]}"
          ;;
        agents|exec|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|doctor|sandbox|apply|queue|archive|delete|migrate-rollouts|unarchive|cloud|features|help)
          exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
          ;;
        *)
          break
          ;;
      esac
    done

    if [ "$explicit_remote" = 1 ]; then
      exec ${codexCliPackage}/bin/codex "''${arguments[@]}"
    fi

    exec ${codexCliPackage}/bin/codex --remote unix:// "''${arguments[@]}"
  '';
}
