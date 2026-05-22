{ pkgs, ... }:
let
  pi-subagents = pkgs.fetchurl {
    url = "https://registry.npmjs.org/pi-subagents/-/pi-subagents-0.25.0.tgz";
    hash = "sha512-HZK1RvT8zfQSzHRExhrnSKdhHmQeCxnpwjkf5dHQbWGcz9kk5C9Cb1rjElEM6CkOGp3eApMm3/HVi2EVYQX7OA==";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-subagents";
  version = "0.25.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents
    mkdir -p "$packageRoot"

    tar -xzf ${pi-subagents} -C "$packageRoot" --strip-components=1

    runHook postInstall
  '';

  meta = {
    description = "Pi package for subagents, chains, parallel execution, and TUI clarification";
    homepage = "https://github.com/nicobailon/pi-subagents";
    license = pkgs.lib.licenses.mit;
  };
}
