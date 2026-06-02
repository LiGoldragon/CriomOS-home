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

    makeWrapper "$out/bin/playwright-cli" "$out/bin/playwright-chrome" \
      --run 'if [ -z "''${PLAYWRIGHT_MCP_EXECUTABLE_PATH:-}" ]; then if command -v google-chrome >/dev/null 2>&1; then export PLAYWRIGHT_MCP_EXECUTABLE_PATH="$(command -v google-chrome)"; elif command -v chromium >/dev/null 2>&1; then export PLAYWRIGHT_MCP_EXECUTABLE_PATH="$(command -v chromium)"; fi; fi' \
      --run 'if [ -z "''${PLAYWRIGHT_MCP_EXTENSION_TOKEN:-}" ]; then token="$(${pkgs.gopass}/bin/gopass show -o chrome-browser/playwright-mcp-extension-token 2>/dev/null || true)"; if [ -n "$token" ]; then export PLAYWRIGHT_MCP_EXTENSION_TOKEN="$token"; fi; unset token; fi'

    runHook postInstall
  '';

  meta = {
    description = "Token-efficient Playwright command-line browser automation for coding agents";
    homepage = "https://github.com/microsoft/playwright-cli";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "playwright-cli";
  };
}
