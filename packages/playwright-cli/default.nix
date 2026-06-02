{ pkgs, ... }:

pkgs.buildNpmPackage {
  pname = "playwright-cli";
  version = "0.1.13";

  src = ./.;

  npmDepsHash = "sha256-xt6b4YEDBy2iygBDrF4nftuJW7+oOJy7T+KYVjpR9eo=";

  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  dontNpmBuild = true;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/playwright-cli"
    cp -r node_modules package.json package-lock.json "$out/lib/playwright-cli/"

    mkdir -p "$out/bin"
    makeWrapper "${pkgs.nodejs}/bin/node" "$out/bin/playwright-cli" \
      --add-flags "$out/lib/playwright-cli/node_modules/@playwright/cli/playwright-cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Token-efficient Playwright command-line browser automation for coding agents";
    homepage = "https://github.com/microsoft/playwright-cli";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "playwright-cli";
  };
}
