{ inputs, pkgs, ... }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-continue";
  version = "0.8.2";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-continue
    mkdir -p "$packageRoot"

    tar -xzf ${inputs.pi-continue-src} -C "$packageRoot" --strip-components=1

    runHook postInstall
  '';

  meta = {
    description = "Pi package for same-session continuation after compaction handoff";
    homepage = "https://github.com/Tiziano-AI/pi-continue";
    license = pkgs.lib.licenses.mit;
  };
}
