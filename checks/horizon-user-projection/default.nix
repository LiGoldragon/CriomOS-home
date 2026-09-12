{ lib, pkgs }:
let
  horizonUser = import ../../lib/horizon-user.nix { inherit lib; };
  projected = horizonUser {
    name = "test-user";
    size = "Large";
    hasPublicKey = true;
    publicKeys = [
      {
        node = "test-node";
        ssh = "ssh-ed25519 test";
        keygrip = "TESTKEYGRIP";
      }
    ];
    resolvedTextSize = "ExtraLarge";
  };
in
assert lib.assertMsg projected.size.min "Large Horizon users must enable the minimum Home profile";
assert lib.assertMsg projected.size.medium
  "Large Horizon users must enable the medium Home profile";
assert lib.assertMsg projected.size.large "Large Horizon users must enable the large Home profile";
assert lib.assertMsg (
  !projected.size.max
) "Large Horizon users must not enable the maximum Home profile";
assert lib.assertMsg projected.hasPubKey "Horizon public-key presence must reach Home";
assert lib.assertMsg (
  projected.pubKeys.test-node.keygrip == "TESTKEYGRIP"
) "Horizon public keys must be indexed by node";
assert lib.assertMsg (
  projected.textSize == "ExtraLarge"
) "Home must consume Horizon's resolved text size";
pkgs.runCommand "horizon-user-projection-check" { } ''
  touch "$out"
''
