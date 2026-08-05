{
  lib,
  pkgs,
  user,
  ...
}:

lib.mkMerge [
  # The CLI is the baseline Bitwarden surface for every managed home.
  (lib.mkIf user.size.min {
    home.packages = [ pkgs.bitwarden-cli ];
  })

  # Keep the Electron desktop closure on the established medium tier.
  (lib.mkIf user.size.medium {
    home.packages = [ pkgs.bitwarden-desktop ];
  })
]
