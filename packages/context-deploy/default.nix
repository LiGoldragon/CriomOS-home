{
  pkgs,
  homeUrl ? "ssh://git@github.com/LiGoldragon/CriomOS-home",
  systemUrl ? "ssh://git@github.com/LiGoldragon/CriomOS",
  # The flake files other flows edit in their checkouts, held through
  # orchestrate while the pins move.
  lockedPaths ? [
    "/git/github.com/LiGoldragon/CriomOS-home/flake.nix"
    "/git/github.com/LiGoldragon/CriomOS-home/flake.lock"
    "/git/github.com/LiGoldragon/CriomOS/flake.nix"
    "/git/github.com/LiGoldragon/CriomOS/flake.lock"
  ],
  # The Lojix host deploy of this node, with @CRIOMOS_REVISION@ where the
  # CriomOS revision goes; null refuses every landing before anything is
  # pinned.
  hostDeploy ? null,
}:
pkgs.writeShellApplication {
  name = "context-deploy";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.git
    pkgs.gnugrep
    pkgs.gnused
    pkgs.jujutsu
  ];
  # nix, orchestrate, lojix and lojix-meta are the system's and the Home
  # profile's, from the unit's PATH.
  text =
    builtins.replaceStrings
      [ "@HOME_URL@" "@SYSTEM_URL@" "@LOCKED_PATHS@" "@HOST_DEPLOY@" ]
      [
        homeUrl
        systemUrl
        (builtins.concatStringsSep " " lockedPaths)
        (if hostDeploy == null then "" else hostDeploy)
      ]
      (builtins.readFile ./context-deploy.sh);
}
