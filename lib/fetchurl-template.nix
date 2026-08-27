# One templated URL primitive shared by package sources and updater metadata.
{ fetchurl, interpolate }:

{
  urlTemplate,
  vars,
  ...
}@args:
fetchurl (
  (builtins.removeAttrs args [
    "urlTemplate"
    "vars"
  ])
  // {
    url = interpolate urlTemplate vars;
  }
)
