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
      output_path=''${request##* }
      output_path=''${output_path%)}
      printf 'fake agent configuration archive\n' > "$output_path"
      printf '(AgentConfigurationWritten %s)\n' "$output_path"
      EOF
      chmod +x "$out/bin/"*
    '';
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
      esac
      output_path=''${request##* }
      output_path=''${output_path%)}
      printf 'fake configuration archive\n' > "$output_path"
      printf '(ConfigurationWritten %s)\n' "$output_path"
      EOF
      cat > "$out/bin/spirit-migrate-production" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      case "$request" in
        *'['* | *']'*) exit 64 ;;
      esac
      target_path=''${request##* }
      target_path=''${target_path%)}
      printf 'fake migrated database\n' > "$target_path"
      printf '(Completed 1)\n'
      EOF
      cat > "$out/bin/spirit-upgrade-store" <<'EOF'
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

  moduleResult = import ../../modules/home/profiles/min/spirit.nix {
    inherit pkgs;
    lib = lib // {
      hm.dag.entryAfter = _after: data: { inherit data; };
      hm.dag.entryBetween = _before: _after: data: { inherit data; };
    };
    inputs = {
      agent = fakeAgent;
      criomos-lib = ../../stubs/criomos-lib;
      spirit = fakeSpirit;
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
      condition = builtins.hasAttr "spirit-daemon" services;
      message = "the schema-derived spirit daemon service must exist.";
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
    exec_start="${services.spirit-daemon.Service.ExecStart}"
    exec_start_pre="${services.spirit-daemon.Service.ExecStartPre}"
    activation_script="${pkgs.writeText "activation" activation}"

    printf '%s\n' "$agent_exec_start" > agent-exec-start
    printf '%s\n' "$agent_exec_start_pre" > agent-exec-start-pre
    printf '%s\n' "$exec_start" > exec-start
    printf '%s\n' "$exec_start_pre" > exec-start-pre
    cat "$activation_script" > activation

    grep -q '/bin/agent-daemon-service$' agent-exec-start
    ! grep -q 'agent-write-configuration' agent-exec-start
    cat "$agent_exec_start" > agent-daemon-service
    grep -q '/bin/agent-daemon ' agent-daemon-service
    grep -q '/agent.config.rkyv$' agent-daemon-service
    grep -q 'gopass show -o goldragon.criome/local-llm-api-token' agent-daemon-service
    agent_configuration_archive="$(${pkgs.gnused}/bin/sed -n 's|.*agent-daemon \([^ ]*agent.config.rkyv\).*|\1|p' agent-daemon-service)"
    test -n "$agent_configuration_archive"
    test -s "$agent_configuration_archive"
    grep -q 'mkdir -p' "$agent_exec_start_pre"
    grep -q '/agent/agent.sock' "$agent_exec_start_pre"

    grep -q '/bin/spirit-daemon ' exec-start
    grep -q '/spirit.config.rkyv$' exec-start
    ! grep -q 'spirit-write-configuration' exec-start
    ! grep -q 'persona-spirit' exec-start

    test -s "$(printf '%s\n' "$exec_start" | ${pkgs.gnused}/bin/sed 's|.* ||')"
    grep -q 'spirit-migrate-production' "$exec_start_pre"
    grep -q 'spirit-upgrade-store' "$exec_start_pre"
    ! grep -q 'ProductionMigrationRequest' "$exec_start_pre"
    grep -q '(\$legacy_database_path \$database_path)' "$exec_start_pre"
    grep -q '(\$database_path)' "$exec_start_pre"
    grep -q '/persona-spirit/v0.5.2/persona-spirit.redb' "$exec_start_pre"
    grep -q '/spirit/spirit.sema' "$exec_start_pre"

    grep -q 'spirit-activation-state' activation
    ! grep -q 'spirit-startup-state' activation
    activation_state="$(sed -n 's|.*\(/nix/store/[^ ]*-spirit-activation-state\).*|\1|p' activation)"
    test -n "$activation_state"
    grep -q 'mkdir -p' "$activation_state"
    grep -q '/agent' "$activation_state"
    ! grep -q 'spirit-migrate-production' "$activation_state"
    ! grep -q 'spirit-upgrade-store' "$activation_state"
    ! grep -q 'rm -f' "$activation_state"

    touch "$out"
  ''
