{ inputs, pkgs, ... }:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  orchestrateModule = ../../modules/home/profiles/min/orchestrate.nix;

  homeDirectory = "/build/orchestrate-nexus-home";
  stateHome = "${homeDirectory}/.local/state";
  stateDirectory = "${stateHome}/orchestrate-nexus";
  runtimeDirectory = "/build/orchestrate-nexus-runtime";
  nexusRuntimeDirectory = "${runtimeDirectory}/orchestrate-nexus";
  ordinarySocketPath = "${nexusRuntimeDirectory}/orchestrate.sock";
  metaSocketPath = "${nexusRuntimeDirectory}/meta-orchestrate.sock";

  moduleResult = import orchestrateModule {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      xdg.stateHome = stateHome;
    };
  };

  moduleConfiguration =
    if moduleResult ? config && moduleResult.config ? content then
      moduleResult.config.content
    else if moduleResult ? content then
      moduleResult.content
    else
      moduleResult;
  service = moduleConfiguration.systemd.user.services.orchestrate-nexus.Service;
  orchestrateProfilePackage = builtins.head moduleConfiguration.home.packages;
  orchestratePackage = inputs.orchestrate.packages.${system}.default;
  assertions = [
    {
      condition = service.StateDirectory == "orchestrate-nexus";
      message = "Orchestrate Nexus must own its fresh state directory.";
    }
    {
      condition = service.StateDirectoryMode == "0700";
      message = "Orchestrate Nexus state must be owner-only.";
    }
    {
      condition = service.RuntimeDirectory == "orchestrate-nexus";
      message = "Orchestrate Nexus must own its runtime directory.";
    }
    {
      condition = service.RuntimeDirectoryMode == "0700";
      message = "Orchestrate Nexus runtime must be owner-only.";
    }
    {
      condition = service.ExecStart == "${orchestratePackage}/bin/orchestrate-nexus";
      message = "Orchestrate Nexus must start with its zero-argument default configuration.";
    }
    {
      condition = !(service ? ExecStartPre);
      message = "Orchestrate Nexus must not use a bootstrap writer or configuration file.";
    }
    {
      condition = builtins.length moduleConfiguration.home.packages == 1;
      message = "Home must install one Orchestrate client wrapper package.";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "orchestrate-nexus-service-path" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
    set -eu

    test -x "${orchestratePackage}/bin/orchestrate-nexus"
    test -x "${orchestrateProfilePackage}/bin/orchestrate"
    test -x "${orchestrateProfilePackage}/bin/meta-orchestrate"
    test -x "${orchestratePackage}/bin/orchestrate-upgrade-preflight"
    test ! -e "${orchestrateProfilePackage}/bin/orchestrate-daemon"
    test ! -e "${orchestratePackage}/bin/orchestrate-write-configuration"

    export HOME=${lib.escapeShellArg homeDirectory}
    export XDG_STATE_HOME=${lib.escapeShellArg stateHome}
    export XDG_RUNTIME_DIR=${lib.escapeShellArg runtimeDirectory}
    mkdir -p "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
    legacy_store="$XDG_STATE_HOME/orchestrate/orchestrate.sema"
    mkdir -p "$(dirname "$legacy_store")"
    touch "$legacy_store"
    test ! -e ${lib.escapeShellArg "${stateDirectory}/orchestrate-nexus.sema"}
    preflight="$(${orchestratePackage}/bin/orchestrate-upgrade-preflight)"
    test "$preflight" = 'active legacy PathLock rows: 0'
    test ! -e ${lib.escapeShellArg "${stateDirectory}/orchestrate-nexus.sema"}

    "${service.ExecStart}" > "$TMPDIR/orchestrate-nexus.log" 2>&1 &
    nexus_pid=$!
    trap 'kill "$nexus_pid" 2>/dev/null || true; wait "$nexus_pid" 2>/dev/null || true' EXIT
    for attempt in $(seq 1 100); do
      test -S ${lib.escapeShellArg ordinarySocketPath} && test -S ${lib.escapeShellArg metaSocketPath} && break
      sleep 0.05
    done
    kill -0 "$nexus_pid"
    test -f ${lib.escapeShellArg "${stateDirectory}/orchestrate-nexus.sema"}
    test -f "$legacy_store"
    test -S ${lib.escapeShellArg ordinarySocketPath}
    test -S ${lib.escapeShellArg metaSocketPath}

    claimed_path=${lib.escapeShellArg "${homeDirectory}/claimed"}
    lock='Lock { lock_id: LockId(1), lock_name: LockName("home-nexus-check"), flow_id: FlowId("home-nexus-check"), lock_paths: LockPaths([LockPath("'"$claimed_path"'")]), lock_reason: LockReason("Home Nexus check") }'
    registration="Lock.{home-nexus-check home-nexus-check [$claimed_path] (Home Nexus check)}"
    registered="$(${orchestrateProfilePackage}/bin/orchestrate "$registration")"
    test "$registered" = "Locked($lock)"
    observed="$(${orchestrateProfilePackage}/bin/orchestrate 'Observe.Locks')"
    test "$observed" = "Observed(Locks(LockSnapshot { locks: Locks([$lock]) }))"
    released="$(${orchestrateProfilePackage}/bin/orchestrate 'Release.{1}')"
    test "$released" = "Released($lock)"
    observed_empty="$(${orchestrateProfilePackage}/bin/orchestrate 'Observe.Locks')"
    test "$observed_empty" = 'Observed(Locks(LockSnapshot { locks: Locks([]) }))'
    configured="$(${orchestrateProfilePackage}/bin/meta-orchestrate 'Configure.{${ordinarySocketPath} ${metaSocketPath}}')"
    test "$configured" = 'Configured.{${ordinarySocketPath} ${metaSocketPath}}'

    touch "$out"
  ''
