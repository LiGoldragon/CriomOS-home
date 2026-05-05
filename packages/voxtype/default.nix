{ pkgs, ... }:

pkgs.voxtype.overrideAttrs (oldAttrs: {
  patches = (oldAttrs.patches or [ ]) ++ [
    ./privacy.patch
  ];
})
