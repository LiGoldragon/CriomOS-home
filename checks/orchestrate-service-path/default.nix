{ inputs, pkgs, ... }:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  orchestrateModule = ../../modules/home/profiles/min/orchestrate.nix;

  homeDirectory = "/build/orchestrate-service-home";
  stateHome = "${homeDirectory}/.local/state";
  stateDirectory = "${stateHome}/orchestrate";
  runtimeDirectory = "/build/orchestrate-service-runtime";
  workspaceRoot = "${homeDirectory}/primary";
  gitIndexRoot = "/git/github.com/LiGoldragon";
  messengerSocketPath = "%t/message/message.sock";

  moduleResult = import orchestrateModule {
    inherit inputs lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      xdg.stateHome = stateHome;
      criomosHome.orchestrate.enable = true;
    };
    horizon.node.services = [
      {
        PersonaDevelopment.capabilities = [ ];
      }
    ];
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;
  service = moduleConfiguration.systemd.user.services.orchestrate-daemon.Service;
  orchestratePackage = inputs.orchestrate.packages.${system}.default;
  expectedExecStart = "${orchestratePackage}/bin/orchestrate-daemon ${stateDirectory}/orchestrate.sema %t/orchestrate/orchestrate.sock %t/orchestrate/orchestrate-owner.sock %t/orchestrate/orchestrate-upgrade.sock ${workspaceRoot} ${gitIndexRoot} messenger=${messengerSocketPath}";
  daemonExecStart = lib.replaceStrings [ "%t" ] [ runtimeDirectory ] service.ExecStart;

  assertions = [
    {
      condition = service.StateDirectory == "orchestrate";
      message = "the daemon service must own its XDG state directory.";
    }
    {
      condition = service.RuntimeDirectory == "orchestrate";
      message = "the daemon service must own its runtime directory.";
    }
    {
      condition = service.RuntimeDirectoryMode == "0700";
      message = "the daemon runtime directory must be owner-only.";
    }
    {
      condition = !(service ? ExecStartPre);
      message = "the removed configuration writer must not be an ExecStartPre step.";
    }
    {
      condition = !(service ? Environment);
      message = "the state-only daemon service must not carry a VCS PATH.";
    }
    {
      condition = service.ExecStart == expectedExecStart;
      message = "the daemon service must render the exact direct startup argv.";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "orchestrate-service-path" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
    set -eu

    test -x "${orchestratePackage}/bin/orchestrate-daemon"
    test ! -e "${orchestratePackage}/bin/orchestrate-write-configuration"

    state_directory=${lib.escapeShellArg stateDirectory}
    runtime_directory=${lib.escapeShellArg runtimeDirectory}
    workspace_root=${lib.escapeShellArg workspaceRoot}
    git_index_root=${lib.escapeShellArg gitIndexRoot}
    test ! -e "$state_directory"
    test ! -e "$runtime_directory"
    test ! -e "$workspace_root"
    test ! -e "$git_index_root"
    mkdir -p "$state_directory" "$runtime_directory"

    # This is the service's evaluated argv after systemd expands %t. Check the
    # complete vector before using it to launch the pinned daemon in this
    # isolated Nix build sandbox.
    set -- ${daemonExecStart}
    test "$#" -eq 8
    test "$1" = "${orchestratePackage}/bin/orchestrate-daemon"
    test "$2" = "$state_directory/orchestrate.sema"
    test "$3" = "$runtime_directory/orchestrate/orchestrate.sock"
    test "$4" = "$runtime_directory/orchestrate/orchestrate-owner.sock"
    test "$5" = "$runtime_directory/orchestrate/orchestrate-upgrade.sock"
    test "$6" = "$workspace_root"
    test "$7" = "$git_index_root"
    test "$8" = "messenger=$runtime_directory/message/message.sock"

    "$@" > "$TMPDIR/orchestrate-daemon.log" 2>&1 &
    daemon_pid=$!
    trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true' EXIT
    for attempt in $(seq 1 100); do
      test -S "$3" && test -S "$4" && test -S "$5" && break
      sleep 0.05
    done
    kill -0 "$daemon_pid"
    test -S "$3"
    test -S "$4"
    test -S "$5"
    test ! -e "$workspace_root"
    test ! -e "$git_index_root"

    touch "$out"
  ''
