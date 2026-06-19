{ inputs, pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-subagents";
  version = "0.29.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents
    mkdir -p "$packageRoot"

    tar -xzf ${inputs.pi-subagents-src} -C "$packageRoot" --strip-components=1

    runHook postInstall
  '';

  meta = {
    description = "Pi package for subagents, chains, parallel execution, and TUI clarification";
    homepage = "https://github.com/nicobailon/pi-subagents";
    license = pkgs.lib.licenses.mit;
  };
}
