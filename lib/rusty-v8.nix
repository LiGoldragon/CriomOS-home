{
  lib,
  stdenv,
  fetchurl,
}:

lib.makeOverridable (
  {
    version,
    hashes,
    profile ? "release",
    baseUrl ? "https://github.com/denoland/rusty_v8/releases/download/v${version}",
    srcBindingHashes ? null,
  }:
  let
    target = stdenv.hostPlatform.rust.rustcTarget;
  in
  fetchurl {
    name = "librusty_v8-${version}";
    url = "${baseUrl}/librusty_v8_${profile}_${target}.a.gz";
    hash = hashes.${stdenv.hostPlatform.system};
    meta.sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    passthru = lib.optionalAttrs (srcBindingHashes != null) {
      srcBinding = fetchurl {
        name = "src_binding-${version}.rs";
        url = "${baseUrl}/src_binding_${profile}_${target}.rs";
        hash = srcBindingHashes.${stdenv.hostPlatform.system};
      };
    };
  }
)
