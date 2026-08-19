{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  expected = {
    agent = "3a3534931be790e63d3db01bbd238ad044b2d35f";
    mentci-src = "235b1b44ecd93857df60c36a2ca4fa16fab5984f";
  };
  mentci = pkgs.callPackage ../../packages/mentci { inherit inputs; };
  agent = inputs.agent.packages.${system}.default;
in
assert lock.nodes.agent.locked.rev == expected.agent;
assert lock.nodes."mentci-src".locked.rev == expected.mentci-src;
pkgs.runCommand "main-contract-pins"
  {
    inherit agent mentci;
  }
  ''
    test -x "$agent/bin/agent"
    test -x "$mentci/bin/mentci"
    touch "$out"
  ''
