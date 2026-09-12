{ lib, pkgs }:
let
  horizonUser = import ../../lib/horizon-user.nix { inherit lib; };
  users = horizonUser.usersByName [
    {
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
    }
  ];
  projected = users.test-user;
in
assert lib.assertMsg (horizonUser.sizeAtLeast projected.size "Min")
  "Large Horizon users must include the minimum Home profile";
assert lib.assertMsg (horizonUser.sizeAtLeast projected.size "Medium")
  "Large Horizon users must include the medium Home profile";
assert lib.assertMsg (horizonUser.sizeAtLeast projected.size "Large")
  "Large Horizon users must include the large Home profile";
assert lib.assertMsg (
  !(horizonUser.sizeAtLeast projected.size "Max")
) "Large Horizon users must not include the maximum Home profile";
assert lib.assertMsg (
  projected.hasPublicKey && (builtins.head projected.publicKeys).keygrip == "TESTKEYGRIP"
) "Home must retain current Horizon public-key fields";
assert lib.assertMsg (
  projected.resolvedTextSize == "ExtraLarge"
) "Home must retain Horizon's resolved text size";
pkgs.runCommand "horizon-user-projection-check" { } ''
  touch "$out"
''
