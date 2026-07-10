{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  fakeAgent = {
    packages.${system}.default = pkgs.runCommand "fake-agent" { } ''
      mkdir -p "$out/bin"
      cat > "$out/bin/agent" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'socket=%s\n' "$AGENT_SOCKET"
      EOF
      cat > "$out/bin/agent-daemon" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'configuration=%s\n' "$1"
      EOF
      cat > "$out/bin/agent-write-configuration" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      case "$request" in
        *'LOCAL_LLM_API_KEY'* | *'goldragon.criome/local-llm-api-token'*) exit 64 ;;
        *'ProviderSeed (deepseek https://api.deepseek.com/v1 deepseek-v4-flash (Gopass platform.deepseek.com/api-key))'*) ;;
        *) exit 65 ;;
      esac
      output_path=''${request##* }
      output_path=''${output_path%))}
      printf 'fake agent configuration archive\n' > "$output_path"
      printf '(AgentConfigurationWritten %s)\n' "$output_path"
      EOF
      chmod +x "$out/bin/"*
    '';
  };

  fakeCodex = {
    packages.${system}.default = pkgs.writeShellScriptBin "codex" "exit 0";
  };


  fakeSpirit = {
    packages.${system}.default = pkgs.runCommand "fake-spirit" { } ''
      mkdir -p "$out/bin"
      cat > "$out/bin/spirit" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'socket=%s\n' "$SPIRIT_SOCKET"
      EOF
      cat > "$out/bin/spirit-daemon" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'configuration=%s\n' "$1"
      EOF
      cat > "$out/bin/spirit-write-configuration" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      case "$request" in
        *'['* | *']'*) exit 64 ;;
        *'ConfigurationWriterGuardianAgent'*) exit 65 ;;
        *'Some (/home/li/.local/state/spirit/spirit-judge.sock None None 180000 None)'*) ;;
        *) exit 66 ;;
      esac
      output_path=''${request##* }
      output_path=''${output_path%))}
      printf 'fake configuration archive\n' > "$output_path"
      printf '(ConfigurationWritten %s)\n' "$output_path"
      EOF
      cat > "$out/bin/spirit-migrate-store" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      case "$request" in
        *'['* | *']'*) exit 64 ;;
      esac
      target_path=''${request#(}
      target_path=''${target_path%)}
      if [ -e "$target_path" ]; then
        printf '(Current 1)\n'
      else
        printf '(Current 0)\n'
      fi
      EOF
      chmod +x "$out/bin/"*
    '';
  };

  fakeSpiritJudge = {
    packages.${system}.default = pkgs.runCommand "fake-spirit-judge" { } ''
      mkdir -p "$out/bin"
      cat > "$out/bin/spirit-judge" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'judge=%s\n' "$*"
      EOF
      chmod +x "$out/bin/spirit-judge"
    '';
  };

  fakeSpiritJudgeConfig = pkgs.runCommand "fake-spirit-judge-config" { } ''
    mkdir -p "$out/prompts"
  '';

  moduleResult = import ../../modules/home/profiles/min/spirit.nix {
    inherit pkgs;
    lib = lib // {
      hm.dag.entryAfter = _after: data: { inherit data; };
      hm.dag.entryBetween = _before: _after: data: { inherit data; };
    };
    inputs = {
      agent = fakeAgent;
      codex-cli = fakeCodex;
      criomos-lib = ../../stubs/criomos-lib;
      spirit = fakeSpirit;
      spirit-judge = fakeSpiritJudge;
      spirit-judge-config = fakeSpiritJudgeConfig;
    };
    config = {
      home.homeDirectory = "/home/li";
      criomosHome.spirit.enable = true;
    };
    horizon = {
      node = {
        typeIs.largeAiRouter = false;
        behavesAs.largeAi = true;
        criomeDomainName = "prometheus.goldragon.criome";
      };
    };
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;

  services = moduleConfiguration.systemd.user.services;
  homePackages = moduleConfiguration.home.packages;
  activation = moduleConfiguration.home.activation.spiritState.data;
  profileWitness = pkgs.symlinkJoin {
    name = "spirit-profile-witness";
    paths = homePackages;
  };

  assertions = [
    {
      condition = builtins.hasAttr "agent-daemon" services;
      message = "the schema-derived agent daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "spirit-judge" services;
      message = "the persistent Spirit judge service must exist.";
    }
    {
      condition = builtins.hasAttr "spirit-daemon" services;
      message = "the schema-derived spirit daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "spirit-judge" services;
      message = "the fail-closed Spirit judge service must exist.";
    }
    {
      condition = builtins.elem "spirit-judge.service" services.spirit-daemon.Unit.Requires;
      message = "the Spirit daemon must require the judgment adapter service.";
    }
    {
      condition = !(builtins.hasAttr "persona-spirit-daemon" services);
      message = "the unversioned persona-spirit daemon service must be absent.";
    }
    {
      condition = !(builtins.hasAttr "persona-spirit-daemon-v0.5.2" services);
      message = "the old persona-spirit v0.5.2 daemon service must be absent.";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "spirit-deployment" { } ''
    set -eu

    test -x "${profileWitness}/bin/spirit"
    test -x "${profileWitness}/bin/agent"
    ! test -e "${profileWitness}/bin/spirit-v0.5.2"
    ! test -e "${profileWitness}/bin/spirit-next"

    SPIRIT_SOCKET=/stale/socket "${profileWitness}/bin/spirit" > current
    grep -q '^socket=/home/li/.local/state/spirit/spirit.sock$' current
    AGENT_SOCKET=/stale/socket "${profileWitness}/bin/agent" > current-agent
    grep -q '^socket=/home/li/.local/state/agent/agent.sock$' current-agent

    agent_exec_start="${services.agent-daemon.Service.ExecStart}"
    agent_exec_start_pre="${services.agent-daemon.Service.ExecStartPre}"
    judge_exec_start="${services.spirit-judge.Service.ExecStart}"
    judge_exec_start_pre="${services.spirit-judge.Service.ExecStartPre}"
    exec_start="${services.spirit-daemon.Service.ExecStart}"
    exec_start_pre="${services.spirit-daemon.Service.ExecStartPre}"
    activation_script="${pkgs.writeText "activation" activation}"

    printf '%s\n' "$agent_exec_start" > agent-exec-start
    printf '%s\n' "$agent_exec_start_pre" > agent-exec-start-pre
    printf '%s\n' "$judge_exec_start" > judge-exec-start
    printf '%s\n' "$judge_exec_start_pre" > judge-exec-start-pre
    printf '%s\n' "$exec_start" > exec-start
    printf '%s\n' "$exec_start_pre" > exec-start-pre
    cat "$activation_script" > activation

    grep -q '/bin/agent-daemon-service$' agent-exec-start
    ! grep -q 'agent-write-configuration' agent-exec-start
    cat "$agent_exec_start" > agent-daemon-service
    grep -q '/bin/agent-daemon ' agent-daemon-service
    grep -q '/agent.config.rkyv$' agent-daemon-service
    ! grep -q 'gopass show' agent-daemon-service
    ! grep -q 'LOCAL_LLM_API_KEY' agent-daemon-service
    agent_configuration_archive="$(${pkgs.gnused}/bin/sed -n 's|.*agent-daemon \([^ ]*agent.config.rkyv\).*|\1|p' agent-daemon-service)"
    test -n "$agent_configuration_archive"
    test -s "$agent_configuration_archive"
    grep -q 'mkdir -p' "$agent_exec_start_pre"
    grep -q '/agent/agent.sock' "$agent_exec_start_pre"

    grep -q '/bin/spirit-judge-daemon-service$' judge-exec-start
    cat "$judge_exec_start" > spirit-judge-daemon-service
    cat "$judge_exec_start_pre" > spirit-judge-startup-state
    grep -q '/spirit-judge.sock' spirit-judge-startup-state

    cat "$judge_exec_start" > spirit-judge-daemon-service
    grep -q -- '--provider openai-codex' spirit-judge-daemon-service
    grep -q -- '--model gpt-5.6-terra' spirit-judge-daemon-service
    grep -q -- '--reasoning-effort medium' spirit-judge-daemon-service
    grep -q -- '--external-authorization-source codex-login' spirit-judge-daemon-service
    grep -q -- '--codex-command ' spirit-judge-daemon-service
    ! grep -q 'gopass show' spirit-judge-daemon-service
    ! grep -q 'bearer-secret-source' spirit-judge-daemon-service
    ! grep -q 'deepseek-v4-pro' spirit-judge-daemon-service

    grep -q '/bin/spirit-daemon ' exec-start
    grep -q '/spirit.config.rkyv$' exec-start
    ! grep -q 'spirit-write-configuration' exec-start
    ! grep -q 'persona-spirit' exec-start

    test -s "$(printf '%s\n' "$exec_start" | ${pkgs.gnused}/bin/sed 's|.* ||')"
    grep -q 'spirit-migrate-store' "$exec_start_pre"
    ! grep -q 'spirit-migrate-production' "$exec_start_pre"
    ! grep -q 'spirit-upgrade-store' "$exec_start_pre"
    grep -q '(\$database_path)' "$exec_start_pre"
    grep -q '/spirit/spirit.sema' "$exec_start_pre"

    grep -q 'spirit-activation-state' activation
    ! grep -q 'spirit-startup-state' activation
    activation_state="$(sed -n 's|.*\(/nix/store/[^ ]*-spirit-activation-state\).*|\1|p' activation)"
    test -n "$activation_state"
    grep -q 'mkdir -p' "$activation_state"
    grep -q '/agent' "$activation_state"
    ! grep -q 'spirit-migrate-store' "$activation_state"
    ! grep -q 'spirit-migrate-production' "$activation_state"
    ! grep -q 'spirit-upgrade-store' "$activation_state"
    ! grep -q 'rm -f' "$activation_state"

    touch "$out"
  ''
