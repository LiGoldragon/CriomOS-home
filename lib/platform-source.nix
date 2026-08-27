# Select a pinned prebuilt artifact and retain the same platform map for its
# declarative updater. Adapted from numtide/llm-agents.nix.
{ stdenv, fetchurlTemplate }:

{
  hashesFile,
  platforms,
  urlTemplate,
}:
let
  versionData = builtins.fromJSON (builtins.readFile hashesFile);
  inherit (versionData) version;
  system = stdenv.hostPlatform.system;
  entry = platforms.${system} or (throw "Unsupported system: ${system}");
  platformVars = if builtins.isAttrs entry then entry else { platform = entry; };
in
{
  inherit version;
  platforms = builtins.attrNames platforms;
  src = fetchurlTemplate {
    inherit urlTemplate;
    vars = {
      inherit version;
    }
    // platformVars;
    hash = versionData.hashes.${system};
  };
  updater = {
    kind = "platform";
    inherit urlTemplate platforms;
  };
}
