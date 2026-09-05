# Convert one public Horizon user projection into the explicit per-user Home
# module argument. Horizon publishes users as a vector; Home configuration
# names are Nix attributes, so the flake maps each entry by its declared name
# before it calls this converter. This is intentionally the only vector-to-name
# boundary in Home.
{ lib }:
raw:
let
  rank = {
    Zero = 0;
    Min = 1;
    Medium = 2;
    Large = 3;
    Max = 4;
  };
  atLeast = magnitude: (rank.${raw.size} or 0) >= rank.${magnitude};
  publicKeys = raw.publicKeys or [ ];
in
raw
// {
  size = {
    min = atLeast "Min";
    medium = atLeast "Medium";
    large = atLeast "Large";
    max = atLeast "Max";
  };
  hasPubKey = raw.hasPublicKey or false;
  pubKeys = builtins.listToAttrs (
    map
      (key: {
        name = key.node;
        value = {
          inherit (key) ssh keygrip;
        };
      })
      publicKeys
  );
  sshPubKey = raw.sshPublicKey or null;
  textSize = raw.resolvedTextSize or raw.textSize or "Medium";
}
