{ inputs, pkgs, ... }:
let
  lib = pkgs.lib // { hm.dag.entryBefore = _dependencies: data: { inherit data; }; };
  system = pkgs.stdenv.hostPlatform.system;
  fakeRelay = pkgs.writeShellScriptBin "relay" ''
    printf '%s\n' "$RELAY_SESSION_ID|$RELAY_TRANSCRIPT|$RELAY_CLUSTER_MEMBERS|$RELAY_FLOW_ROUTES|$*"
  '';
  fixtureInputs = inputs // {
    message.packages.${system}.default = fakeRelay;
  };
  result = lib.evalModules {
    specialArgs = {
      inputs = fixtureInputs;
      inherit pkgs;
      user.size = "Min";
    };
    modules = [
      ../../modules/home/deployments/cf7879-cluster-relay.nix
      ({ lib, ... }: {
        options = {
          home.homeDirectory = lib.mkOption { type = lib.types.str; };
          home.packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          criomos.corePackages.claude = lib.mkOption { type = lib.types.package; };
        };
        config = {
          home.homeDirectory = "/build/cluster-relay-home";
          criomos.corePackages.claude = pkgs.hello;
          criomosHome.clusterRelay.enable = true;
          criomosHome.clusterRelay.runtimeRouteFile = null;
        };
      })
    ];
  };
  package = builtins.head result.config.home.packages;
in
pkgs.runCommand "cluster-relay-package" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  test -x ${package}/bin/cluster-relay
  test -x ${inputs.message.packages.${system}.default}/bin/relay
  test "$(${package}/bin/cluster-relay one two 2>&1 || true)" = "cluster-relay: FLOW_ID is not a configured cf7879 member"
  FLOW_ID=57a7aa ${package}/bin/cluster-relay 'first six words are supplied here' 'last six words are supplied here' > "$TMPDIR/output"
  grep -F '57a7aa02-e52d-4266-8746-6770ff770d11|/build/cluster-relay-home/.claude/projects/-git-github-com-LiGoldragon-secondary/57a7aa02-e52d-4266-8746-6770ff770d11.jsonl' "$TMPDIR/output"
  grep -F 'cf7879@01a0a715-2d5d-7342-b278-1dbcf78795bd' "$TMPDIR/output"
  touch "$out"
''
