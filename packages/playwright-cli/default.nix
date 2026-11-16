{ pkgs, extensionTokenEntry ? null, ... }:
let
  browserRead = import ./browser-read.nix { inherit pkgs; };
  tokenGuard = ''
    if [ "''${PLAYWRIGHT_MCP_EXTENSION_TOKEN+set}" = set ]; then
      if [ -z "$PLAYWRIGHT_MCP_EXTENSION_TOKEN" ]; then
        printf '%s\n' 'playwright-chrome: PLAYWRIGHT_MCP_EXTENSION_TOKEN is empty' >&2
        exit 1
      fi
    else
      tokenEntry=${pkgs.lib.escapeShellArg (if extensionTokenEntry == null then "" else extensionTokenEntry)}
      if [ -z "$tokenEntry" ]; then
        printf '%s\n' 'playwright-chrome: secret entry is not configured' >&2
        exit 1
      fi
      if ! token="$(${pkgs.gopass}/bin/gopass show -o "$tokenEntry" 2>/dev/null)"; then
        printf 'playwright-chrome: cannot read secret entry %s\n' "$tokenEntry" >&2
        exit 1
      fi
      if [ -z "$token" ]; then
        printf 'playwright-chrome: secret entry %s is empty\n' "$tokenEntry" >&2
        exit 1
      fi
      export PLAYWRIGHT_MCP_EXTENSION_TOKEN="$token"
      unset token tokenEntry
    fi
  '';
in
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
      --run ${pkgs.lib.escapeShellArg tokenGuard} \
      --run 'if [ -z "''${PLAYWRIGHT_MCP_EXECUTABLE_PATH:-}" ]; then if command -v google-chrome >/dev/null 2>&1; then export PLAYWRIGHT_MCP_EXECUTABLE_PATH="$(command -v google-chrome)"; elif command -v chromium >/dev/null 2>&1; then export PLAYWRIGHT_MCP_EXECUTABLE_PATH="$(command -v chromium)"; fi; fi'

    makeWrapper "${pkgs.nodejs}/bin/node" "$out/bin/browser-read" \
      --add-flags ${pkgs.lib.escapeShellArg (toString browserRead)} \
      --add-flags "$out/bin/playwright-chrome"

    runHook postInstall
  '';

  meta = {
    description = "Token-efficient Playwright command-line browser automation for coding agents";
    homepage = "https://github.com/microsoft/playwright-cli";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "playwright-cli";
  };
}
