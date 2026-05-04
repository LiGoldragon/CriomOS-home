{ pkgs, ... }:
let
  pi-linkup = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@aliou/pi-linkup/-/pi-linkup-0.10.3.tgz";
    hash = "sha512-I33b1lN+2JBqpnhxb8Sjg2gRqZ6jNsoTUbpSv60lklZl806t+uliE2AQfS4GzlUjSa0dCGKAvtAwyerDm+ngPg==";
  };

  pi-utils-ui = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@aliou/pi-utils-ui/-/pi-utils-ui-0.1.5.tgz";
    hash = "sha512-YQwv22pzjhdPmFRA1s0dQcX8UqXh2igO0NRRyRbgVhXA65MFCPVKvo5+Zh17XJH73s9Gpijn/ibCwkD5g3QMUA==";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-linkup";
  version = "0.10.3";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-linkup
    mkdir -p "$packageRoot" "$packageRoot/.pi-deps/pi-utils-ui" "$packageRoot/node_modules/@aliou"

    tar -xzf ${pi-linkup} -C "$packageRoot" --strip-components=1
    tar -xzf ${pi-utils-ui} -C "$packageRoot/.pi-deps/pi-utils-ui" --strip-components=1
    ln -s ../../.pi-deps/pi-utils-ui "$packageRoot/node_modules/@aliou/pi-utils-ui"

    runHook postInstall
  '';

  meta = {
    description = "Pi extension for Linkup web search, answers, and fetch";
    homepage = "https://github.com/aliou/pi-linkup";
    license = pkgs.lib.licenses.mit;
  };
}
