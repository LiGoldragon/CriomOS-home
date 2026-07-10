{ inputs, pkgs, ... }:
pkgs.buildNpmPackage {
  pname = "pi-subagents";
  version = "0.34.0+fork";

  src = inputs.pi-subagents-src;
  npmDepsHash = "sha256-IJJ3hceNvHUr5QFIa/+0tnxNiEPh7jifE9dvPHrLE58=";
  dontNpmBuild = true;
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents
    mkdir -p "$packageRoot"
    cp -r agents install.mjs package.json package-lock.json prompts README.md CHANGELOG.md skills src node_modules "$packageRoot"

    runHook postInstall
  '';

  meta = {
    description = "Pi package for subagents, chains, parallel execution, and TUI clarification";
    homepage = "https://github.com/LiGoldragon/pi-subagents-nicobailon";
    license = pkgs.lib.licenses.mit;
  };
}
