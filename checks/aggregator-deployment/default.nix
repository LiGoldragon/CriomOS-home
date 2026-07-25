{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  fakeHomeDirectory = "/build/fable/account";
  fakeWorkspace = "${fakeHomeDirectory}/primary";
  fakeStateHome = "${fakeHomeDirectory}/.local/state";
  expectedClaudeProjectRoot = "${fakeHomeDirectory}/.claude/projects/-build-fable-account-primary";

  fakeAggregatorPackage = pkgs.runCommand "fake-aggregator" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/aggregator" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    request=$(cat)
    printf 'aggregator configuration=%s request=%s\n' "$AGGREGATOR_CONFIGURATION" "$request"
    EOF
    cat > "$out/bin/meta-aggregator" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    request=$(cat)
    printf 'meta-aggregator configuration=%s request=%s\n' "$AGGREGATOR_CONFIGURATION" "$request"
    EOF
    cat > "$out/bin/aggregator-daemon" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    printf 'daemon configuration=%s\n' "$AGGREGATOR_CONFIGURATION"
    EOF
    cat > "$out/bin/aggregator-write-configuration" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    configuration_path="''${AGGREGATOR_CONFIGURATION:-}"
    local_default=false
    home_directory=""
    user_identifier=""
    temporary_directory=""
    runtime_directory=""
    store_path=""
    workspace=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --configuration)
          configuration_path="$2"
          shift 2
          ;;
        --local-default)
          local_default=true
          shift
          ;;
        --home-directory)
          home_directory="$2"
          shift 2
          ;;
        --user-identifier)
          user_identifier="$2"
          shift 2
          ;;
        --temporary-directory)
          temporary_directory="$2"
          shift 2
          ;;
        --runtime-directory)
          runtime_directory="$2"
          shift 2
          ;;
        --store-path)
          store_path="$2"
          shift 2
          ;;
        --workspace)
          workspace="$2"
          shift 2
          ;;
        *)
          printf 'unexpected argument: %s\n' "$1" >&2
          exit 64
          ;;
      esac
    done
    test -n "$configuration_path"
    if [ "$local_default" != true ]; then
      printf 'local default mode is required\n' >&2
      exit 66
    fi
    test -n "$home_directory"
    test -n "$user_identifier"
    test -n "$temporary_directory"
    test -n "$runtime_directory"
    test -n "$store_path"
    test -n "$workspace"
    normalized_workspace="''${workspace%/}"
    encoded_workspace="''${normalized_workspace//\//-}"
    claude_project_root="$home_directory/.claude/projects/$encoded_workspace"
    claude_subagent_output_root="$temporary_directory/claude-$user_identifier"
    mkdir -p \
      "$claude_project_root" \
      "$claude_subagent_output_root" \
      "$(dirname "$configuration_path")" \
      "$runtime_directory" \
      "$(dirname "$store_path")"
    request="($runtime_directory/aggregator.sock 384 $runtime_directory/aggregator-meta.sock 384 $store_path [] [(Claude ($claude_project_root)) (ClaudeSubagentOutput ($claude_subagent_output_root))] MetadataOnly (32 4096) ((DaemonLocalStorePath OpaqueStaleCapable FragileReferenceAscending) (64 4096 65536 1024) []))"
    case "$request" in
      *'LegacyReports'* | *'LegacyAgentOutputs'* | *'reports/'* | *'agent-outputs/'*) exit 65 ;;
    esac
    case "$request" in
      *' 432 '* | *' 438 '*) printf 'socket modes must be user-only\n' >&2; exit 67 ;;
    esac
    printf '%s\n' "$request" > "$configuration_path"
    printf '%s\n' "$request"
    EOF
    chmod +x "$out/bin/"*
  '';

  fakeAggregator = {
    packages.${system}.default = fakeAggregatorPackage;
  };

  moduleResult = import ../../modules/home/profiles/min/aggregator.nix {
    inherit pkgs;
    lib = lib // {
      hm.dag.entryAfter = _after: data: { inherit data; };
      hm.dag.entryBetween = _before: _after: data: { inherit data; };
    };
    inputs = {
      aggregator = fakeAggregator;
    };
    config = {
      home.homeDirectory = fakeHomeDirectory;
      xdg.stateHome = fakeStateHome;
      criomosHome.aggregator = {
        enable = true;
        workspacePaths = [ fakeWorkspace ];
      };
    };
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;

  services = moduleConfiguration.systemd.user.services;
  homePackages = moduleConfiguration.home.packages;
  profileWitness = pkgs.symlinkJoin {
    name = "aggregator-profile-witness";
    paths = homePackages;
  };

  assertions = [
    {
      condition = builtins.hasAttr "aggregator-daemon" services;
      message = "the aggregator daemon user service must exist.";
    }
    {
      condition = !(builtins.hasAttr "aggregator-reports-daemon" services);
      message = "legacy report scraping service names must be absent.";
    }
    {
      condition = !(
        builtins.hasAttr "activation" moduleConfiguration.home
        && builtins.hasAttr "aggregatorState" moduleConfiguration.home.activation
      );
      message = "aggregator runtime state must initialize from the user service, not Home Manager activation.";
    }
    {
      condition = services.aggregator-daemon.Service.RuntimeDirectory == "aggregator";
      message = "the aggregator user service must own its runtime directory.";
    }
    {
      condition = services.aggregator-daemon.Service.RuntimeDirectoryMode == "0700";
      message = "the aggregator runtime directory must be user-only.";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "aggregator-deployment" { } ''
    set -eu

    test -x "${profileWitness}/bin/aggregator"
    test -x "${profileWitness}/bin/meta-aggregator"
    test -x "${profileWitness}/bin/aggregator-daemon"
    test -x "${profileWitness}/bin/aggregator-write-configuration"

    exec_start_pre="${services.aggregator-daemon.Service.ExecStartPre}"
    exec_start="${services.aggregator-daemon.Service.ExecStart}"
    configuration_path="${fakeStateHome}/aggregator/configuration.nota"

    printf '%s\n' "$exec_start_pre" > exec-start-pre
    printf '%s\n' "$exec_start" > exec-start

    grep -q 'aggregator-startup-state' exec-start-pre
    grep -q '/bin/aggregator-daemon$' exec-start
    default_configuration_script=$(grep -o '[^ ]*aggregator-default-configuration' "$exec_start_pre")
    grep -q -- '--local-default' "$default_configuration_script"
    grep -q -- '--workspace ${fakeWorkspace}' "$default_configuration_script"
    ! grep -q 'reports' "$default_configuration_script"
    ! grep -q 'agent-outputs' "$default_configuration_script"
    ! grep -q -- '-home-li-primary\|/home/li\|/tmp/claude-1001\|/tmp/claude-' "$default_configuration_script"

    mkdir -p "$PWD/runtime" "$PWD/temp-root"
    TMPDIR="$PWD/temp-root" XDG_RUNTIME_DIR="$PWD/runtime" "$exec_start_pre"
    test -s "$configuration_path"
    grep -q '${expectedClaudeProjectRoot}' "$configuration_path"
    grep -q "$PWD/temp-root/claude-" "$configuration_path"
    grep -q 'MetadataOnly' "$configuration_path"
    grep -q 'DaemonLocalStorePath OpaqueStaleCapable FragileReferenceAscending' "$configuration_path"
    ! grep -q -- '-home-li-primary\|/home/li\|/tmp/claude-1001\|/tmp/claude-' "$configuration_path"
    ! grep -q 'LegacyReports\|LegacyAgentOutputs\|reports/\|agent-outputs/' "$configuration_path"

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/aggregator" <<'EOF' > health
    (ObserveHealth (home-profile-health))
    EOF
    grep -q '^aggregator configuration=${fakeStateHome}/aggregator/configuration.nota request=(ObserveHealth (home-profile-health))$' health

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/aggregator" <<'EOF' > sessions
    (ListSessions (home-profile-sessions None (10 1 None None NewestFirst)))
    EOF
    grep -q '^aggregator configuration=${fakeStateHome}/aggregator/configuration.nota request=(ListSessions ' sessions

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/meta-aggregator" <<'EOF' > meta
    (ObserveConfiguration (home-profile-meta))
    EOF
    grep -q '^meta-aggregator configuration=${fakeStateHome}/aggregator/configuration.nota request=(ObserveConfiguration (home-profile-meta))$' meta

    touch "$out"
  ''
