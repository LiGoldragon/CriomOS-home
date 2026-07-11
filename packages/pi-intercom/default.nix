{ inputs, pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-intercom";
  version = "0.6.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-intercom
    mkdir -p \
      "$packageRoot" \
      "$packageRoot/.pi-deps/tsx" \
      "$packageRoot/.pi-deps/typebox" \
      "$packageRoot/.pi-deps/esbuild" \
      "$packageRoot/.pi-deps/esbuild-linux-x64" \
      "$packageRoot/.pi-deps/get-tsconfig" \
      "$packageRoot/.pi-deps/resolve-pkg-maps" \
      "$packageRoot/node_modules/@esbuild"

    tar -xzf ${inputs.pi-intercom-src} -C "$packageRoot" --strip-components=1
    tar -xzf ${inputs.pi-intercom-tsx-src} -C "$packageRoot/.pi-deps/tsx" --strip-components=1
    tar -xzf ${inputs.pi-intercom-typebox-src} -C "$packageRoot/.pi-deps/typebox" --strip-components=1
    tar -xzf ${inputs.pi-intercom-esbuild-src} -C "$packageRoot/.pi-deps/esbuild" --strip-components=1
    tar -xzf ${inputs.pi-intercom-esbuild-linux-x64-src} -C "$packageRoot/.pi-deps/esbuild-linux-x64" --strip-components=1
    tar -xzf ${inputs.pi-intercom-get-tsconfig-src} -C "$packageRoot/.pi-deps/get-tsconfig" --strip-components=1
    tar -xzf ${inputs.pi-intercom-resolve-pkg-maps-src} -C "$packageRoot/.pi-deps/resolve-pkg-maps" --strip-components=1

    ln -s ../.pi-deps/tsx "$packageRoot/node_modules/tsx"
    ln -s ../.pi-deps/typebox "$packageRoot/node_modules/typebox"
    ln -s ../.pi-deps/esbuild "$packageRoot/node_modules/esbuild"
    ln -s ../.pi-deps/get-tsconfig "$packageRoot/node_modules/get-tsconfig"
    ln -s ../.pi-deps/resolve-pkg-maps "$packageRoot/node_modules/resolve-pkg-maps"
    ln -s ../../.pi-deps/esbuild-linux-x64 "$packageRoot/node_modules/@esbuild/linux-x64"

    runHook postInstall
  '';

  meta = {
    description = "Pi extension for local inter-session communication";
    homepage = "https://github.com/LiGoldragon/pi-intercom";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
