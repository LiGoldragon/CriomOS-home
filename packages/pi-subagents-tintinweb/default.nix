{
  inputs,
  pkgs,
  source ? {
    kind = "directory";
    path = inputs.pi-subagents-tintinweb-src;
  },
  ...
}:
let
  sourceInstallCommand =
    if source.kind == "tarball" then
      ''
        tar -xzf ${source.path} -C "$packageRoot" --strip-components=1
      ''
    else if source.kind == "directory" then
      ''
        cp -R ${source.path}/. "$packageRoot"/
      ''
    else
      throw "Unsupported pi-subagents-tintinweb source kind: ${source.kind}";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-subagents-tintinweb";
  version = "0.13.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents-tintinweb
    mkdir -p \
      "$packageRoot" \
      "$packageRoot/.pi-deps/typebox" \
      "$packageRoot/.pi-deps/croner" \
      "$packageRoot/.pi-deps/nanoid" \
      "$packageRoot/node_modules/@sinclair" \
      "$packageRoot/node_modules/croner" \
      "$packageRoot/node_modules/nanoid"

  ''
  + sourceInstallCommand
  + ''
    tar -xzf ${inputs.pi-subagents-tintinweb-typebox-src} -C "$packageRoot/.pi-deps/typebox" --strip-components=1
    tar -xzf ${inputs.pi-subagents-tintinweb-croner-src} -C "$packageRoot/.pi-deps/croner" --strip-components=1
    tar -xzf ${inputs.pi-subagents-tintinweb-nanoid-src} -C "$packageRoot/.pi-deps/nanoid" --strip-components=1

    rmdir "$packageRoot/node_modules/croner" "$packageRoot/node_modules/nanoid"
    ln -s ../../.pi-deps/typebox "$packageRoot/node_modules/@sinclair/typebox"
    ln -s ../.pi-deps/croner "$packageRoot/node_modules/croner"
    ln -s ../.pi-deps/nanoid "$packageRoot/node_modules/nanoid"

    runHook postInstall
  '';

  meta = {
    description = "Tintinweb Pi subagents extension packaged for the CriomOS Pi profile";
    homepage = "https://github.com/tintinweb/pi-subagents";
    license = pkgs.lib.licenses.mit;
  };
}
