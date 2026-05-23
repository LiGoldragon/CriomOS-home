{ inputs, pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-linkup";
  version = "0.10.3";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-linkup
    mkdir -p "$packageRoot" "$packageRoot/.pi-deps/pi-utils-ui" "$packageRoot/node_modules/@aliou"

    tar -xzf ${inputs.pi-linkup-src} -C "$packageRoot" --strip-components=1
    tar -xzf ${inputs.pi-utils-ui-src} -C "$packageRoot/.pi-deps/pi-utils-ui" --strip-components=1
    ln -s ../../.pi-deps/pi-utils-ui "$packageRoot/node_modules/@aliou/pi-utils-ui"

    runHook postInstall
  '';

  meta = {
    description = "Pi extension for Linkup web search, answers, and fetch";
    homepage = "https://github.com/aliou/pi-linkup";
    license = pkgs.lib.licenses.mit;
  };
}
