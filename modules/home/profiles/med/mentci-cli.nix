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
lib.mkIf size.is.med {
  home.packages = [ inputs.mentci-tools.packages.${system}.cli ];
}
