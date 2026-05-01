{
  lib,
  pkgs,
  user,
  inputs,
  ...
}:
let
  inherit (user) size;
  system = pkgs.stdenv.hostPlatform.system;
in
lib.mkIf size.atLeastMed {
  home.packages = [
    inputs.substack-cli.packages.${system}.default
    inputs.gascity.packages.${system}.default

    # Gas City + bd share the same MEOW stack at runtime: bd drives
    # beads, dolt persists them, tmux/flock/lsof/pgrep are the
    # process-supervision tools `gc` shells out to.
    pkgs.beads
    pkgs.dolt
    pkgs.tmux
    pkgs.lsof
    pkgs.procps      # pgrep
    pkgs.util-linux  # flock
  ];
}
