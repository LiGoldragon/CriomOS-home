{
  lib,
  pkgs,
  user,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
in
lib.mkMerge [
  # The CLI is the baseline Bitwarden surface for every managed home.
  (lib.mkIf (sizeAtLeast "Min") {
    home.packages = [ pkgs.bitwarden-cli ];
  })

  # Keep the Electron desktop closure on the established medium tier.
  (lib.mkIf (sizeAtLeast "Medium") {
    home.packages = [ pkgs.bitwarden-desktop ];
  })
]
