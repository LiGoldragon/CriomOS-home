{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  expectedRevision = "54710fabbab7c47ce19764a98e7153e5c93a49f4";
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  lockedRevision = lock.nodes.lojix.locked.rev;
  client = inputs.lojix.packages.${system}.default;
  bootstrap = inputs.lojix.packages.${system}.lojix-bootstrap;
in
assert lockedRevision == expectedRevision;
pkgs.runCommand "lojix-ownership"
  {
    inherit client bootstrap;
  }
  ''
    test -x "$client/bin/lojix"
    test -x "$bootstrap/bin/lojix-bootstrap"
    touch "$out"
  ''
