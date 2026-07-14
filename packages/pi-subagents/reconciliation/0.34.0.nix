{ pkgs }:

pkgs.buildNpmPackage {
  pname = "pi-subagents-reconciliation-witness";
  version = "0.34.0";

  src = pkgs.fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-subagents";
    rev = "12a157d2a70b2f4cbc004c020c5f9213b6d8eea8";
    hash = "sha256-RN8f5cT/oRSkqwOAmvJ2uJsOmScYb0ijwixTd75iGHk=";
  };

  patches = [ ./0.31.0-to-0.34.0.patch ];
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
}
