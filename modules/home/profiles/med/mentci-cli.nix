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
  home.packages = [ inputs.mentci-tools.packages.${system}.cli ];
}
