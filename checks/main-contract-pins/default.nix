{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  expected = {
    agent = "3a3534931be790e63d3db01bbd238ad044b2d35f";
  };
  agent = inputs.agent.packages.${system}.default;
in
assert lock.nodes.agent.locked.rev == expected.agent;
pkgs.runCommand "main-contract-pins"
  {
    inherit agent;
  }
  ''
    test -x "$agent/bin/agent"
    touch "$out"
  ''
