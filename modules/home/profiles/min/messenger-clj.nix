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
  # messenger-clj and its hm-* commands reach PATH through the Home profile.
  config = lib.mkIf (sizeAtLeast "Min" && system == "x86_64-linux") {
    home.packages = [ messengerCljPackage ];
  };
}
