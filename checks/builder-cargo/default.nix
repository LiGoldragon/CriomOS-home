# The builder Cargo command exists where this node is the master of a
# synchronization whose replica is one of its Nix builders, with that host and
# tree; elsewhere it is absent. Its script passes shellcheck by being built.
{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  homeFor =
    nodeName: synchronizations:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        user = {
          name = "example";
          inherit synchronizations;
        };
        horizon = {
          node = {
            name = nodeName;
            builderConfigs = [ { hostName = "builder.example.criome"; } ];
          };
          exNodes = {
            builder.criomeDomainName = "builder.example.criome";
            other.criomeDomainName = "other.example.criome";
          };
        };
      };
      modules = [
        ../../modules/home/unison.nix
        ../../modules/home/builder-cargo.nix
        {
          home.username = "example";
          home.homeDirectory = "/home/example";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  toBuilder = [
    {
      master = "laptop";
      replica = "builder";
      tree = "Code";
    }
  ];
  laptop = homeFor "laptop" toBuilder;
  replica = homeFor "builder" toBuilder;
  toOther = homeFor "laptop" [
    {
      master = "laptop";
      replica = "other";
      tree = "Code";
    }
  ];
  command = lib.findFirst (p: (p.name or "") == "builder-cargo") null laptop.home.packages;
in
assert laptop.criomosHome.builderCargo.enable;
assert laptop.criomosHome.builderCargo.host == "builder.example.criome";
assert laptop.criomosHome.builderCargo.tree == "Code";
assert !replica.criomosHome.builderCargo.enable;
assert !toOther.criomosHome.builderCargo.enable;
assert command != null;
pkgs.runCommand "builder-cargo-check" { } ''
  grep -F "/home/example/Code" ${command}/bin/builder-cargo
  grep -F "builder.example.criome" ${command}/bin/builder-cargo
  cd /
  status=0
  ${command}/bin/builder-cargo build 2>reply || status=$?
  test "$status" -eq 2
  grep -F "outside the synchronized tree" reply
  touch "$out"
''
