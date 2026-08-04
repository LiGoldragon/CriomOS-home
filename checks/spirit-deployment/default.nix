{
  inputs,
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  maintainedSpiritPackages = inputs.spirit.packages.${system};
  maintainedSpiritArtifacts = inputs.spirit.lib.${system}.mkUserServiceArtifacts {
    stateDirectory = "/home/li/.local/state/spirit";
  };

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

  fakeSpiritPackage = pkgs.runCommand "fake-spirit" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/spirit" <<'EOF'
    #!${pkgs.runtimeShell}
    test "$#" = 1
    test "$1" = Version
    printf 'socket=%s\n' "$SPIRIT_SOCKET"
    EOF
    cat > "$out/bin/meta-spirit" <<'EOF'
    #!${pkgs.runtimeShell}
    test "$#" = 1
    test "$1" = ObserveHead
    printf 'meta-socket=%s\n' "$SPIRIT_META_SOCKET"
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

  fakeSpiritJudgePackage = pkgs.runCommand "fake-spirit-judge" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/spirit-judge" <<'EOF'
    #!${pkgs.runtimeShell}
    printf 'judge=%s\n' "$*"
    EOF
    chmod +x "$out/bin/spirit-judge"
  '';

  fakeSpiritJudgeConfig = pkgs.runCommand "fake-spirit-judge-config" { } ''
    mkdir -p "$out/prompts"
  '';
  fakeSpiritJudgeProvider = pkgs.writeShellScriptBin "codex" "exit 0";

  fakeSpirit = {
    packages.${system} = {
      default = fakeSpiritPackage;
      daemon = fakeSpiritPackage;
      configuration-writer = fakeSpiritPackage;
      store-migration = fakeSpiritPackage;
      judge = fakeSpiritJudgePackage;
      judge-config = fakeSpiritJudgeConfig;
      judge-provider = fakeSpiritJudgeProvider;
    };

    lib.${system}.mkUserServiceArtifacts =
      { stateDirectory }:
      let
        socketPath = "${stateDirectory}/spirit.sock";
        metaSocketPath = "${stateDirectory}/meta-spirit.sock";
        judgeSocketPath = "${stateDirectory}/spirit-judge.sock";
        databasePath = "${stateDirectory}/spirit.sema";
        configurationPath = "spirit.config.rkyv";
        daemonConfiguration = pkgs.runCommand "fake-spirit-daemon-configuration" { } ''
          mkdir -p "$out"
          ${fakeSpiritPackage}/bin/spirit-write-configuration \
            "(ConfigurationWriteRequest (${socketPath} (Some ${metaSocketPath}) ${databasePath} None Gating (Some (${judgeSocketPath} None None 180000 None)) $out/${configurationPath}))" \
            > "$out/configuration-written.dotos"
        '';
        activateState = pkgs.writeShellScript "spirit-activation-state" ''
          ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg stateDirectory}
        '';
        initializeState = pkgs.writeShellScript "spirit-startup-state" ''
          state_directory=${lib.escapeShellArg stateDirectory}
          database_path=${lib.escapeShellArg databasePath}
          ${pkgs.coreutils}/bin/mkdir -p "$state_directory"
          ${pkgs.coreutils}/bin/rm -f \
            ${lib.escapeShellArg socketPath} \
            ${lib.escapeShellArg metaSocketPath}
          ${fakeSpiritPackage}/bin/spirit-migrate-store "($database_path)"
        '';
        initializeJudgeState = pkgs.writeShellScript "spirit-judge-startup-state" ''
          ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg stateDirectory}
          ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg judgeSocketPath}
        '';
        daemonServiceWrapper = pkgs.writeShellScriptBin "spirit-daemon-service" ''
          exec ${fakeSpiritPackage}/bin/spirit-daemon \
            ${daemonConfiguration}/${configurationPath}
        '';
        judgeServiceWrapper = pkgs.writeShellScriptBin "spirit-judge-daemon-service" ''
          exec ${fakeSpiritJudgePackage}/bin/spirit-judge \
            ${lib.escapeShellArg "(Serve (${judgeSocketPath} ${fakeSpiritJudgeConfig} OpenAiCodex gpt-5.6-luna (Some XHigh) 180000 None None (Some codex-login) (Some ${pkgs.util-linux}/bin/setsid) (Some ${fakeSpiritJudgeProvider}/bin/codex) None))"}
        '';
        commandLineWrapper = pkgs.writeShellScriptBin "spirit" ''
          export SPIRIT_SOCKET=${lib.escapeShellArg socketPath}
          exec ${fakeSpiritPackage}/bin/spirit "$@"
        '';
        metaSpiritCommandLineWrapper = pkgs.writeShellScriptBin "meta-spirit" ''
          export SPIRIT_META_SOCKET=${lib.escapeShellArg metaSocketPath}
          exec ${fakeSpiritPackage}/bin/meta-spirit "$@"
        '';
      in
      {
        paths = {
          inherit
            configurationPath
            databasePath
            judgeSocketPath
            metaSocketPath
            socketPath
            stateDirectory
            ;
        };
        packages = {
          spirit = fakeSpiritPackage;
          judge = fakeSpiritJudgePackage;
          judgeConfig = fakeSpiritJudgeConfig;
          judgeProvider = fakeSpiritJudgeProvider;
        };
        inherit
          activateState
          commandLineWrapper
          daemonConfiguration
          daemonServiceWrapper
          initializeJudgeState
          initializeState
          judgeServiceWrapper
          metaSpiritCommandLineWrapper
          ;
      };
  };

  moduleResult = import ../../modules/home/profiles/min/spirit.nix {
    inherit pkgs;
    lib = lib // {
      hm.dag.entryAfter = after: data: { inherit after data; };
      hm.dag.entryBetween = before: after: data: { inherit before after data; };
    };
    inputs = {
      agent = fakeAgent;
      criomos-lib = ../../stubs/criomos-lib;
      spirit = fakeSpirit;
    };
    config = {
      home.homeDirectory = "/home/li";
      xdg.configHome = "/home/li/.config";
      criomosHome.spirit.enable = true;
    };
    horizon = {
      node = {
        services = [
          {
            PersonaDevelopment = {
              capabilities = [ ];
            };
          }
        ];
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
  overrideMigration = moduleConfiguration.home.activation.removeObsoleteSpiritJudgeOverride;
  profileWitness = pkgs.symlinkJoin {
    name = "spirit-profile-witness";
    paths = homePackages;
  };
  liveJudgeOverrideTarget = pkgs.writeShellScriptBin "spirit-judge-daemon-service" "exit 0";

  assertions = [
    {
      condition = builtins.all (name: builtins.hasAttr name maintainedSpiritPackages) [
        "default"
        "daemon"
        "configuration-writer"
        "store-migration"
        "judge"
        "judge-config"
        "judge-provider"
      ];
      message = "the maintained Spirit flake must export the complete service package set.";
    }
    {
      condition = builtins.all (name: builtins.hasAttr name maintainedSpiritArtifacts) [
        "paths"
        "packages"
        "daemonConfiguration"
        "activateState"
        "initializeState"
        "initializeJudgeState"
        "daemonServiceWrapper"
        "judgeServiceWrapper"
        "commandLineWrapper"
        "metaSpiritCommandLineWrapper"
      ];
      message = "the maintained Spirit flake must export coherent Home service artifacts.";
    }
    {
      condition = maintainedSpiritArtifacts.paths.stateDirectory == "/home/li/.local/state/spirit";
      message = "the maintained Spirit service constructor must preserve Home's supplied state path.";
    }
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
      condition = overrideMigration.before == [ "reloadSystemd" ];
      message = "the obsolete judge drop-in migration must run before systemd reload.";
    }
    {
      condition = overrideMigration.after == [ "linkGeneration" ];
      message = "the obsolete judge drop-in migration must run after generation linking.";
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

    grep -q 'mkUserServiceArtifacts' ${../../modules/home/profiles/min/spirit.nix}
    ! grep -q 'inputs\.spirit\.packages' ${../../modules/home/profiles/min/spirit.nix}
    ! grep -q 'inputs\.spirit-judge' ${../../modules/home/profiles/min/spirit.nix}
    ! grep -q 'inputs\.spirit-judge-config' ${../../modules/home/profiles/min/spirit.nix}
    ! grep -q 'inputs\.codex-cli' ${../../modules/home/profiles/min/spirit.nix}
    ! grep -q 'spirit-judge\.url' ${../../flake.nix}
    ! grep -q 'spirit-judge-config = {' ${../../flake.nix}

    SPIRIT_SOCKET=/stale/socket "${profileWitness}/bin/spirit" Version > current
    grep -q '^socket=/home/li/.local/state/spirit/spirit.sock$' current
    SPIRIT_META_SOCKET=/stale/socket "${profileWitness}/bin/meta-spirit" ObserveHead > current-meta
    grep -q '^meta-socket=/home/li/.local/state/spirit/meta-spirit.sock$' current-meta
    AGENT_SOCKET=/stale/socket "${profileWitness}/bin/agent" > current-agent
    grep -q '^socket=/home/li/.local/state/agent/agent.sock$' current-agent

    agent_exec_start="${services.agent-daemon.Service.ExecStart}"
    agent_exec_start_pre="${services.agent-daemon.Service.ExecStartPre}"
    judge_exec_start="${services.spirit-judge.Service.ExecStart}"
    judge_exec_start_pre="${services.spirit-judge.Service.ExecStartPre}"
    exec_start="${services.spirit-daemon.Service.ExecStart}"
    exec_start_pre="${services.spirit-daemon.Service.ExecStartPre}"
    activation_script="${pkgs.writeText "activation" activation}"
    override_migration_activation_script="${pkgs.writeText "override-migration-activation" overrideMigration.data}"

    printf '%s\n' "$agent_exec_start" > agent-exec-start
    printf '%s\n' "$agent_exec_start_pre" > agent-exec-start-pre
    printf '%s\n' "$judge_exec_start" > judge-exec-start
    printf '%s\n' "$judge_exec_start_pre" > judge-exec-start-pre
    printf '%s\n' "$exec_start" > exec-start
    printf '%s\n' "$exec_start_pre" > exec-start-pre
    cat "$activation_script" > activation
    cat "$override_migration_activation_script" > override-migration-activation

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
    # spirit-judge takes exactly one argument: a NOTA payload, not argv flags.
    ! grep -q -- ' --' spirit-judge-daemon-service
    grep -q -- 'OpenAiCodex' spirit-judge-daemon-service
    grep -q -- 'gpt-5.6-luna' spirit-judge-daemon-service
    grep -q -- '(Some XHigh)' spirit-judge-daemon-service
    ! grep -q -- 'gpt-5.6-terra' spirit-judge-daemon-service
    ! grep -q -- '(Some Medium)' spirit-judge-daemon-service
    grep -q -- '(Some codex-login)' spirit-judge-daemon-service
    grep -q -- '/bin/setsid' spirit-judge-daemon-service
    grep -q -- '/bin/codex' spirit-judge-daemon-service
    ! grep -q 'gopass show' spirit-judge-daemon-service
    ! grep -q 'deepseek-v4-pro' spirit-judge-daemon-service

    grep -q '/bin/spirit-daemon-service$' exec-start
    cat "$exec_start" > spirit-daemon-service
    grep -q '/bin/spirit-daemon ' spirit-daemon-service
    grep -q '/spirit.config.rkyv$' spirit-daemon-service
    ! grep -q 'spirit-write-configuration' spirit-daemon-service
    ! grep -q 'persona-spirit' spirit-daemon-service

    daemon_configuration_archive="$(
      ${pkgs.gnused}/bin/sed -n 's|^[[:space:]]*\([^ ]*spirit.config.rkyv\)$|\1|p' \
        spirit-daemon-service
    )"
    test -s "$daemon_configuration_archive"
    grep -q 'spirit-migrate-store' "$exec_start_pre"
    ! grep -q 'spirit-migrate-production' "$exec_start_pre"
    ! grep -q 'spirit-upgrade-store' "$exec_start_pre"
    grep -q '(\$database_path)' "$exec_start_pre"
    grep -q '/spirit/spirit.sema' "$exec_start_pre"

    grep -q 'spirit-activation-state' activation
    ! grep -q 'spirit-startup-state' activation
    activation_state="$(sed -n 's|.*\(/nix/store/[^ ]*-spirit-activation-state\).*|\1|p' activation)"
    agent_activation_state="$(sed -n 's|.*\(/nix/store/[^ ]*-agent-activation-state\).*|\1|p' activation)"
    test -n "$activation_state"
    test -n "$agent_activation_state"
    grep -q 'mkdir -p' "$activation_state"
    ! grep -q '/agent' "$activation_state"
    grep -q '/agent' "$agent_activation_state"
    ! grep -q 'spirit-migrate-store' "$activation_state"
    ! grep -q 'spirit-migrate-production' "$activation_state"
    ! grep -q 'spirit-upgrade-store' "$activation_state"
    ! grep -q 'rm -f' "$activation_state"

    override_migration_executable="$(${pkgs.gnused}/bin/sed -n \
      's|.*\(/nix/store/[^ ]*/bin/migrate-obsolete-spirit-judge-override\).*|\1|p' \
      override-migration-activation)"
    test -x "$override_migration_executable"
    grep -q '/systemd/user/spirit-judge.service.d/override.conf' override-migration-activation

    fixtures="$TMPDIR/obsolete-spirit-judge-override-fixtures"
    mkdir -p "$fixtures/absent"
    "$override_migration_executable" "$fixtures/absent/override.conf"
    ! test -e "$fixtures/absent/override.conf"

    stale_hash=00000000000000000000000000000000
    stale_executable="/nix/store/''${stale_hash}-spirit-judge-daemon-service/bin/spirit-judge-daemon-service"
    mkdir -p "$fixtures/recognized-stale"
    printf '[Service]\nExecStart=\nExecStart=%s\n' "$stale_executable" \
      > "$fixtures/recognized-stale/override.conf"
    "$override_migration_executable" "$fixtures/recognized-stale/override.conf"
    ! test -e "$fixtures/recognized-stale/override.conf"

    mkdir -p "$fixtures/unexpected-command"
    printf '[Service]\nExecStart=\nExecStart=/bin/false\n' \
      > "$fixtures/unexpected-command/override.conf"
    if "$override_migration_executable" "$fixtures/unexpected-command/override.conf"; then
      echo 'migration accepted an unexpected override command' >&2
      exit 1
    fi
    test -f "$fixtures/unexpected-command/override.conf"

    mkdir -p "$fixtures/extra-line"
    printf '[Service]\nExecStart=\nExecStart=%s\nUnexpected=yes\n' "$stale_executable" \
      > "$fixtures/extra-line/override.conf"
    if "$override_migration_executable" "$fixtures/extra-line/override.conf"; then
      echo 'migration accepted an override with extra content' >&2
      exit 1
    fi
    test -f "$fixtures/extra-line/override.conf"

    mkdir -p "$fixtures/live-executable"
    printf '[Service]\nExecStart=\nExecStart=%s\n' \
      "${liveJudgeOverrideTarget}/bin/spirit-judge-daemon-service" \
      > "$fixtures/live-executable/override.conf"
    if "$override_migration_executable" "$fixtures/live-executable/override.conf"; then
      echo 'migration removed an override whose executable is still live' >&2
      exit 1
    fi
    test -f "$fixtures/live-executable/override.conf"

    ln -s "$fixtures/unexpected-command/override.conf" "$fixtures/symlink-override.conf"
    if "$override_migration_executable" "$fixtures/symlink-override.conf"; then
      echo 'migration followed an override symlink' >&2
      exit 1
    fi
    test -L "$fixtures/symlink-override.conf"

    touch "$out"
  ''
