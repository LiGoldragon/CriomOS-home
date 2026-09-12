# Home consumes Horizon's current user projection directly. These functions
# perform only the two operations required at the flake/module boundary:
# naming vector entries for Nix outputs and comparing the declared size enum.
{ lib }:
let
  sizeOrder = [
    "Zero"
    "Min"
    "Medium"
    "Large"
    "Max"
  ];
in
{
  usersByName = users: builtins.listToAttrs (map (user: lib.nameValuePair user.name user) users);

  sizeAtLeast =
    actual: required:
    let
      index = size: lib.lists.findFirstIndex (candidate: candidate == size) null sizeOrder;
      actualIndex = index actual;
      requiredIndex = index required;
    in
    assert lib.assertMsg (actualIndex != null) "Unknown Horizon user size ${actual}";
    assert lib.assertMsg (requiredIndex != null) "Unknown required Horizon user size ${required}";
    actualIndex >= requiredIndex;
}
