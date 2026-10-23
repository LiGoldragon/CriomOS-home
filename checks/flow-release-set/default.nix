{ pkgs, inputs, ... }:
let
  fakeRuntime = pkgs.symlinkJoin {
    name = "flow-release-fixture";
    paths = map (name: pkgs.writeShellScriptBin name ''
      printf '%s|%s|%s\n' "$0" "''${FLOW_SOCKET-}" "''${FLOW_META_SOCKET-}"
    '') [ "flow" "flow-meta" "flow-nexus" "flow-hook" "flow-store-check" ];
  };
  releaseSet = pkgs.callPackage ../../packages/flow-release-set {
    inherit inputs;
    selected = "stable";
    releases = {
      stable = {
        generation = "stable-fixture";
        runtime = fakeRuntime;
        runtimeDirectory = "flow-release-stable-fixture";
      };
      last = null;
      next = {
        generation = "next-fixture";
        runtime = fakeRuntime;
        runtimeDirectory = "flow-release-next-fixture";
      };
    };
  };
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      ../../modules/home/profiles/min/flow-release-set.nix
      {
        home.username = "release-fixture";
        home.homeDirectory = "/home/release-fixture";
        home.stateVersion = "26.05";
        criomosHome.flow.releaseSet = {
          enable = true;
          stable = {
            generation = "stable-fixture";
            package = fakeRuntime;
          };
          last = null;
          next = {
            generation = "next-fixture";
            package = fakeRuntime;
          };
        };
      }
    ];
  };
  services = home.config.systemd.user.services;
  stableService = services.flow-nexus-release-stable.Service;
  nextService = services.flow-nexus-release-next.Service;
  text = value: if builtins.isList value then pkgs.lib.concatStringsSep " " value else value;
in
assert !(services ? flow-nexus-release-last);
assert pkgs.lib.hasInfix "%t/flow-release-stable-fixture/flow.sock" (text stableService.ExecStart);
assert pkgs.lib.hasInfix "%h/.local/state/flow-release-stable-fixture/flow.sema" (text stableService.ExecStart);
assert builtins.elem "HERDR_SESSION=flow-stable-fixture" stableService.Environment;
assert pkgs.lib.hasInfix "%t/flow-release-next-fixture/flow-meta.sock" (text nextService.ExecStart);
assert builtins.elem "HERDR_SESSION=flow-next-fixture" nextService.Environment;
pkgs.runCommand "flow-release-set-contract" { } ''
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  test "$(readlink ${releaseSet}/bin/flow)" = "${releaseSet}/bin/flow-stable"
  ${releaseSet}/bin/flow-stable > stable.out
  grep -F "$XDG_RUNTIME_DIR/flow-release-stable-fixture/flow.sock" stable.out
  ${releaseSet}/bin/flow-next > next.out
  grep -F "$XDG_RUNTIME_DIR/flow-release-next-fixture/flow.sock" next.out
  test ! -e ${releaseSet}/bin/flow-last
  touch "$out"
''
