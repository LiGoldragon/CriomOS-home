{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
  # A distinct injected canonical package proves consumers select the option,
  # rather than independently repeating a version or constructor.
  selected = pkgs.writeShellScriptBin "codex" ''
    printf '%s\n' "$CODEX_HOME" "$@"
  '';
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
assert
  birdNext
  == "${selected}/bin/codex app-server --remote-control --listen unix:///home/bird/.codex-next/app-server-control/app-server-control.sock";
assert (next bird).Environment == [ "CODEX_HOME=/home/bird/.codex-next" ];
assert lib.hasSuffix
  "-codex-next-0.158.0-alpha.9/bin/codex app-server --remote-control --listen unix:///home/li/.codex-next/app-server-control/app-server-control.sock"
  liNext;
assert lib.hasSuffix "-codex-0.153.4/bin/codex app-server --remote-control --listen unix://"
  liStable;
# This correction does not retire or upgrade Bird's other occupied endpoint.
assert lib.hasSuffix "-codex-0.153.4/bin/codex app-server --remote-control --listen unix://"
  birdStable;
assert
  builtins.attrNames bird.systemd.user.services == [
    "codex-remote-control"
    "codex-remote-control-next"
  ];
pkgs.runCommand "bird-codex-matched-selection" { } ''
    ${birdClient}/bin/codex 'argument with spaces' > actual
    cat > expected <<'EXPECTED'
  /home/bird/.codex-next
  --remote
  unix:///home/bird/.codex-next/app-server-control/app-server-control.sock
  argument with spaces
  EXPECTED
    cmp actual expected
    # No Bird auth bootstrap or copy is introduced by its new preparation script.
    if grep -Eq 'auth.json|config.toml|install -m600' ${builtins.head (next bird).ExecStartPre}; then
      echo 'Bird upgrade must preserve auth in place, not bootstrap another copy' >&2
      exit 1
    fi
    grep -F -- '-codex-next-0.158.0-alpha.9/bin/codex --remote' ${liClient}/bin/codex
    touch "$out"
''
