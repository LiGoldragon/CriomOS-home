{ inputs, pkgs, ... }:
# The Home Harness service from the pinned Harness revision: the unit runs
# harness-daemon-launch in its own runtime directory, the clients default to
# that directory's sockets, and the installed launcher plus the installed
# harness-usage client answer one usage read end to end on a fixture home.
let
  system = pkgs.stdenv.hostPlatform.system;
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  ownedAgentModule = { ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; };
  user = {
    name = "harness-user";
    size = "Min";
  };
  configuration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs user ownedAgentPackages;
      horizon = {
        node = {
          services = [ ];
        };
        exNodes = { };
        users = [ user ];
      };
      hexis = inputs.hexis.packages.${system}.default;
    };
    modules = [
      ownedAgentModule
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/harness.nix
      {
        home = {
          username = user.name;
          homeDirectory = "/home/${user.name}";
          stateVersion = "26.05";
        };
      }
    ];
  };
  harnessPackage = inputs.harness.packages.${system}.default;
  service = configuration.config.systemd.user.services.harness-daemon;
  clients = pkgs.buildEnv {
    name = "harness-user-service-clients";
    paths = configuration.config.home.packages;
  };
in
assert pkgs.lib.toList service.Service.ExecStart == [ "${harnessPackage}/bin/harness-daemon-launch" ];
assert pkgs.lib.toList service.Service.RuntimeDirectory == [ "harness" ];
assert pkgs.lib.toList service.Service.RuntimeDirectoryMode == [ "0700" ];
assert pkgs.lib.toList service.Install.WantedBy == [ "default.target" ];
pkgs.runCommand "harness-user-service" { } ''
  set -eu
  export HOME="$TMPDIR/home"
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  export TZ=UTC
  mkdir -p "$HOME" "$XDG_RUNTIME_DIR/harness"
  chmod 0700 "$XDG_RUNTIME_DIR/harness"

  RUNTIME_DIRECTORY="$XDG_RUNTIME_DIR/harness" ${harnessPackage}/bin/harness-daemon-launch &
  daemon=$!
  for _ in $(seq 1 100); do
    [ -S "$XDG_RUNTIME_DIR/harness/harness.sock" ] && break
    sleep 0.05
  done
  test -S "$XDG_RUNTIME_DIR/harness/harness.sock"
  test -S "$XDG_RUNTIME_DIR/harness/meta-harness.sock"
  test -S "$XDG_RUNTIME_DIR/harness/supervision.sock"

  ${clients}/bin/harness-usage > "$TMPDIR/view"
  ${clients}/bin/harness UsageSnapshotQuery > "$TMPDIR/typed"
  kill "$daemon"

  grep -q '^Claude: unavailable (credentials absent)$' "$TMPDIR/view"
  grep -q '^Codex: unavailable (no live control socket)$' "$TMPDIR/view"
  grep -q '^planning projection: not configured$' "$TMPDIR/view"
  grep -q '^UsageSnapshot\.{' "$TMPDIR/typed"
  touch "$out"
''
