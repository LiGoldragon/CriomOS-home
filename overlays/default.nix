{ inputs }:
[
  (import ./claude-desktop.nix { inherit inputs; })
  (import ./yt-dlp.nix { inherit inputs; })
]
