{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
  # The stable endpoint is the independently pinned package selected by Home.
  selected = pkgs.callPackage ../../owned-agents/codex { };
  fakeClaude = pkgs.writeShellScriptBin "claude" "exit 0";
  fakeHexis = pkgs.writeShellScriptBin "hexis" "exit 0";
  testInputs = inputs // {
    hexis.lib.mkManagedConfig = { lib, ... }: lib.hm.dag.entryAfter [ "writeBoundary" ] "";
  };
  mkConfiguration =
    name:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inputs = testInputs;
        user = {
          inherit name;
          capabilities = lib.optional (name == "bird") "StableCodex";
          size = "Max";
          hasPublicKey = true;
        };
        horizon.node.behavesAs.edge = false;
        hexis = fakeHexis;
      };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-remote-control.nix
        ../../modules/home/profiles/min/codex-next.nix
        {
          home.username = name;
          home.homeDirectory = "/home/${name}";
          home.stateVersion = "26.05";
          criomos.corePackages.codex = selected;
          criomos.corePackages.claude = fakeClaude;
        }
      ];
    }).config;
  bird = mkConfiguration "bird";
  li = mkConfiguration "li";
  next = configuration: configuration.systemd.user.services.codex-remote-control-next.Service;
  stable = configuration: configuration.systemd.user.services.codex-remote-control.Service;
  birdClient = builtins.head (
    builtins.filter (package: lib.getName package == "codex") bird.home.packages
  );
  liClient = builtins.head (
    builtins.filter (package: lib.getName package == "codex") li.home.packages
  );
  birdNext = builtins.head (next bird).ExecStart;
  liNext = builtins.head (next li).ExecStart;
  liStable = builtins.head (stable li).ExecStart;
  birdStable = builtins.head (stable bird).ExecStart;
in
assert bird.criomosHome.codexNext.rawClientPackage == selected;
assert birdClient == selected;
assert liClient == selected;
assert
  birdNext
  == "${selected}/bin/codex app-server --remote-control --listen unix:///home/bird/.codex-next/app-server-control/app-server-control.sock";
assert (next bird).Environment == [ "CODEX_HOME=/home/bird/.codex-next" ];
assert builtins.isString (next bird).ExecStartPre;
assert lib.hasSuffix
  "-codex-next-${(pkgs.callPackage ../../owned-agents/codex-next { }).version}/bin/codex app-server --remote-control --listen unix:///home/li/.codex-next/app-server-control/app-server-control.sock"
  liNext;
assert lib.hasSuffix "-codex-${selected.version}/bin/codex app-server --remote-control --listen unix://"
  liStable;
# This correction does not retire or upgrade Bird's other occupied endpoint.
assert lib.hasSuffix "-codex-${selected.version}/bin/codex app-server --remote-control --listen unix://"
  birdStable;
assert
  builtins.attrNames bird.systemd.user.services == [
    "codex-remote-control"
    "codex-remote-control-next"
  ];
pkgs.runCommand "bird-codex-matched-selection" { } ''
    # No Bird auth bootstrap or copy is introduced by its new preparation script.
    if grep -Eq 'auth.json|config.toml|install -m600' ${(next bird).ExecStartPre}; then
      echo 'Bird upgrade must preserve auth in place, not bootstrap another copy' >&2
      exit 1
    fi
    touch "$out"
''
