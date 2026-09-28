# Home consumes Horizon's current user projection directly. These functions
# perform only the two operations required at the flake/module boundary:
# naming map entries for Nix outputs and querying the declared size ladder.
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
  usersByName = users: users;

  sizeAtLeast =
    actual: required:
    let
      field = lib.toLower required;
    in
    assert lib.assertMsg (builtins.elem required (builtins.tail sizeOrder)) "Unknown required Horizon user size ${required}";
    assert lib.assertMsg (builtins.hasAttr field actual) "Horizon user size lacks ${field}";
    actual.${field};
}
