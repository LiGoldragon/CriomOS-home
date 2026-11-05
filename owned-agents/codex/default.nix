{
  lib,
  stdenvNoCC,
  fetchurl,
  manifestFile ? ./hashes.json,
  ...
}:
let
  manifest = builtins.fromJSON (builtins.readFile manifestFile);
  version = manifest.version;
  targets = builtins.mapAttrs (_: artifact: {
    inherit (artifact) target;
    inherit (artifact.cli) hash;
    inherit (artifact.cli) url;
    hostHash = artifact.codeModeHost.hash;
    hostUrl = artifact.codeModeHost.url;
  }) manifest.targets;
in
assert manifest.strategy == "prebuilt";
(import ../../lib/mk-codex-prebuilt.nix { inherit lib stdenvNoCC fetchurl; }) {
  pname = "codex";
  inherit version targets;
  description = "Locally promoted, reproducibly pinned Codex CLI";
  passthru.releaseManifest = manifest;
  meta = {
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
  };
}
