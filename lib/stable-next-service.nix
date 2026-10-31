# Stable and next are two named service slots. The declaration supplies every
# identity-bearing value as data; the executable does not choose a slot.
{ lib }:
let
  slot =
    {
      unitName,
      package,
      ordinarySocket,
      metaSocket ? null,
      memory ? null,
      pairedNexusEndpoints ? { },
    }:
    {
      inherit
        unitName
        package
        ordinarySocket
        metaSocket
        memory
        pairedNexusEndpoints
        ;
    };
in
{
  inherit slot;

  pair =
    {
      stable,
      next,
    }:
    {
      stable = slot stable;
      next = slot next;
    };
}
