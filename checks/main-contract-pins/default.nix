{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  expected = {
    agent = "3a3534931be790e63d3db01bbd238ad044b2d35f";
    mentci-src = "aa2ce64448aeba01b20009a7a5a87070d6d9679b";
    mentci-egui = "f8b86ffeab51d61953000a58f20fb0cac9933845";
  };
  mentci = pkgs.callPackage ../../packages/mentci { inherit inputs; };
  mentciEgui = inputs.mentci-egui.packages.${system}.default;
  agent = inputs.agent.packages.${system}.default;
in
assert lock.nodes.agent.locked.rev == expected.agent;
assert lock.nodes."mentci-src".locked.rev == expected.mentci-src;
assert lock.nodes."mentci-egui".locked.rev == expected.mentci-egui;
pkgs.runCommand "main-contract-pins"
  {
    inherit agent mentci mentciEgui;
  }
  ''
    test -x "$agent/bin/agent"
    test -x "$mentci/bin/mentci"
    test -x "$mentciEgui/bin/mentci-egui"
    touch "$out"
  ''
