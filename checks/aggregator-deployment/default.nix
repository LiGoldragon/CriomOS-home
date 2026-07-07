{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

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
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --configuration)
          configuration_path="$2"
          shift 2
          ;;
        *)
          printf 'unexpected argument: %s\n' "$1" >&2
          exit 64
          ;;
      esac
    done
    test -n "$configuration_path"
    request=$(cat)
    case "$request" in
      *'LegacyReports'* | *'LegacyAgentOutputs'* | *'reports/'* | *'agent-outputs/'*) exit 65 ;;
      *'[(Claude ('*'/.claude/projects/-home-li-primary)) (ClaudeSubagentOutput (/tmp/claude-'*'))]'*) ;;
      *) printf 'missing configured transcript roots in %s\n' "$request" >&2; exit 66 ;;
    esac
    case "$request" in
      *' 432 '* | *' 438 '*) printf 'socket modes must be user-only\n' >&2; exit 67 ;;
    esac
    mkdir -p "$(dirname "$configuration_path")"
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
      home.homeDirectory = "/build/home/li";
      xdg.stateHome = "/build/home/li/.local/state";
      criomosHome.aggregator.enable = true;
    };
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;

  services = moduleConfiguration.systemd.user.services;
  homePackages = moduleConfiguration.home.packages;
  activation = moduleConfiguration.home.activation.aggregatorState.data;
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
    activation_script="${pkgs.writeText "activation" activation}"
    configuration_path="/build/home/li/.local/state/aggregator/configuration.nota"

    printf '%s\n' "$exec_start_pre" > exec-start-pre
    printf '%s\n' "$exec_start" > exec-start
    cat "$activation_script" > activation

    grep -q 'aggregator-startup-state' exec-start-pre
    grep -q '/bin/aggregator-daemon$' exec-start
    grep -q 'aggregator-default-configuration' activation
    ! grep -q 'reports' activation
    ! grep -q 'agent-outputs' activation

    mkdir -p "$PWD/runtime"
    XDG_RUNTIME_DIR="$PWD/runtime" "$exec_start_pre"
    test -s "$configuration_path"
    grep -q '/.claude/projects/-home-li-primary' "$configuration_path"
    grep -q '/tmp/claude-' "$configuration_path"
    grep -q 'MetadataOnly' "$configuration_path"
    grep -q 'DaemonLocalStorePath OpaqueStaleCapable FragileReferenceAscending' "$configuration_path"
    ! grep -q 'LegacyReports\|LegacyAgentOutputs\|reports/\|agent-outputs/' "$configuration_path"

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/aggregator" <<'EOF' > health
    (ObserveHealth (home-profile-health))
    EOF
    grep -q '^aggregator configuration=/build/home/li/.local/state/aggregator/configuration.nota request=(ObserveHealth (home-profile-health))$' health

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/aggregator" <<'EOF' > sessions
    (ListSessions (home-profile-sessions None (10 1 None None NewestFirst)))
    EOF
    grep -q '^aggregator configuration=/build/home/li/.local/state/aggregator/configuration.nota request=(ListSessions ' sessions

    AGGREGATOR_CONFIGURATION=/stale/socket "${profileWitness}/bin/meta-aggregator" <<'EOF' > meta
    (ObserveConfiguration (home-profile-meta))
    EOF
    grep -q '^meta-aggregator configuration=/build/home/li/.local/state/aggregator/configuration.nota request=(ObserveConfiguration (home-profile-meta))$' meta

    touch "$out"
  ''
