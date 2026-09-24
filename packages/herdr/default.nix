{ inputs, pkgs }:

inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr.overrideAttrs (previous: {
  patches = (previous.patches or [ ]) ++ [ ../../patches/herdr/codex-executable-selection.patch ];
})
