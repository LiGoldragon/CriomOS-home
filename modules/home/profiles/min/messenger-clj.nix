{
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  system = pkgs.stdenv.hostPlatform.system;
  messengerCljPackage = inputs.messenger-clj.packages.${system}.default;
in
{
  config = lib.mkIf (sizeAtLeast "Min" && system == "x86_64-linux") {
    home.packages = [ messengerCljPackage ];
  };
}
