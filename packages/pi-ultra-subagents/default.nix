{ inputs, pkgs, ... }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-ultra-subagents";
  version = "0.1.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-ultra-subagents
    mkdir -p \
      "$packageRoot" \
      "$packageRoot/.pi-deps/typebox" \
      "$packageRoot/node_modules"

    tar -xzf ${inputs.pi-ultra-subagents-src} -C "$packageRoot" --strip-components=1
    tar -xzf ${inputs.pi-ultra-subagents-typebox-src} -C "$packageRoot/.pi-deps/typebox" --strip-components=1

    ln -s ../.pi-deps/typebox "$packageRoot/node_modules/typebox"

    runHook postInstall
  '';

  meta = {
    description = "Pi package for isolated child subagents and structured result merging";
    homepage = "https://github.com/liangxiao777/pi-ultra-subagents";
    license = pkgs.lib.licenses.mit;
  };
}
