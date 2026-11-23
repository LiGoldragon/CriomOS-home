{ pkgs, ... }:
pkgs.buildNpmPackage (finalAttrs: {
  pname = "pi";
  version = "1.6.0";

  # The official release asset contains the model catalog used by this build.
  src = pkgs.fetchurl {
    url = "https://github.com/earendil-works/pi/releases/download/v${finalAttrs.version}/pi-${finalAttrs.version}-source.tar.gz";
    hash = "sha256-FFGeKI6E5xNimyILtq3mgY4y1P8j8gX9gKfMSd7cQT4=";
  };

  patches = [
    ./patches/complete-pasted-skill-blocks-are-loaded.patch
    ./patches/preserve-active-action-space-for-pi-docs.patch
    ./patches/extension-context-theme-persistence.patch
  ];

  npmDepsHash = "sha256-V7fRy44X50tqfFewWQ/k5UjvUt+AoMOZkTw/v0bib6o=";
  nodejs = pkgs.nodejs_24;
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build:offline";
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-monorepo
    cp -r apps packages node_modules package.json $out/lib/pi-monorepo/

    mkdir -p $out/bin
    makeWrapper "${pkgs.lib.getExe pkgs.nodejs_24}" "$out/bin/pi" \
      --add-flags "$out/lib/pi-monorepo/packages/coding-agent/dist/bundle/cli.js" \
      --suffix PATH : "${pkgs.lib.makeBinPath [ pkgs.nodejs_24 ]}" \
      --prefix PATH : "${pkgs.lib.makeBinPath (with pkgs; [ fd ripgrep wl-clipboard xclip ])}" \
      --run 'if [ -z "''${PI_PACKAGE_DIR:-}" ]; then export PI_PACKAGE_DIR="$HOME/.local/share/criomos/pi/package"; fi' \
      --run 'export LINKUP_API_KEY="''${LINKUP_API_KEY:-$(${pkgs.gopass}/bin/gopass show -o linkup.so/api-key 2>/dev/null || true)}"'

    runHook postInstall
  '';

  nativeBuildInputs = [ pkgs.makeWrapper pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.libxcb pkgs.libcap_ng ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm exec --workspace=@earendil-works/pi-coding-agent -- vitest run \
      test/skills.test.ts test/system-prompt.test.ts test/extensions-runner.test.ts
    runHook postCheck
  '';

  meta = {
    description = "pi — coding agent CLI from earendil-works/pi";
    homepage = "https://github.com/earendil-works/pi";
    license = pkgs.lib.licenses.mit;
    mainProgram = "pi";
  };
})
