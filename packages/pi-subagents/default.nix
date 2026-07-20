{ inputs, pkgs, ... }:
pkgs.buildNpmPackage {
  pname = "pi-subagents";
  version = "0.36.3";

  src = inputs.pi-subagents-src;
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-FMWJkMWyyfdn/7QRFEs8doI4MWLVMVa4b03ao+tNmD8=";
  dontNpmBuild = true;
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents
    mkdir -p "$packageRoot"
    cp -r agents index.ts install.mjs package.json package-lock.json prompts README.md CHANGELOG.md skills src node_modules "$packageRoot"

    runHook postInstall
  '';

  meta = {
    description = "Pi package for subagents, chains, parallel execution, and TUI clarification";
    homepage = "https://github.com/LiGoldragon/pi-subagents-nicobailon";
    license = pkgs.lib.licenses.mit;
  };
}
