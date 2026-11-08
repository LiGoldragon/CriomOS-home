{ pkgs, ... }:

# cf: Cloudflare's official command-line tool (npm package cf, repository
# cloudflare/cf, packages/cli). nixpkgs cloudflare-cli is a different,
# unofficial tool. The wrapper reads CLOUDFLARE_API_TOKEN from gopass at
# cloudflare.com/api-token when cf runs, unless the caller set it; the
# token reaches cf's process alone, never the shell.
pkgs.buildNpmPackage {
  pname = "cf";
  version = "1.0.0-beta.28";

  src = ./.;

  npmDepsHash = "sha256-f/RkmoO1gpiDcgI75n6AuKFgSCnW2yVFSYVTN2rOP14=";

  nodejs = pkgs.nodejs_24;

  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  # workerd, the local Workers runtime miniflare starts, ships as a
  # prebuilt binary; it is patched to run on NixOS.
  nativeBuildInputs = [ pkgs.makeWrapper pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/cf"
    cp -r node_modules package.json package-lock.json "$out/lib/cf/"
    find "$out/lib/cf/node_modules/@cloudflare" -maxdepth 1 -name 'workerd-*' ! -name 'workerd-linux-64' -exec rm -rf {} +

    mkdir -p "$out/bin"
    makeWrapper "${pkgs.nodejs_24}/bin/node" "$out/bin/cf" \
      --add-flags "$out/lib/cf/node_modules/cf/bin/cf" \
      --run 'if [ -z "''${CLOUDFLARE_API_TOKEN:-}" ]; then token="$(${pkgs.gopass}/bin/gopass show -o cloudflare.com/api-token 2>/dev/null || true)"; if [ -n "$token" ]; then export CLOUDFLARE_API_TOKEN="$token"; fi; unset token; fi'

    runHook postInstall
  '';

  meta = {
    description = "Cloudflare's official command-line tool";
    homepage = "https://github.com/cloudflare/cf";
    license = with pkgs.lib.licenses; [ mit asl20 ];
    mainProgram = "cf";
  };
}
