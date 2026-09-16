{ pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "core-heartbeat-source";
  version = "99285db";
  src = ./source;
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/share/core-heartbeat"
    cp -R . "$out/share/core-heartbeat/"
  '';
}
