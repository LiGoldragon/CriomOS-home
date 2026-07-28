{ pkgs }:
pkgs.writeShellApplication {
  name = "criomos-ensure-nix-profile-link";
  runtimeInputs = [ pkgs.coreutils ];
  text = builtins.readFile ./ensure-nix-profile-link.sh;
}
