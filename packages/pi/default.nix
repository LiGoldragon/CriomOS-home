{ pkgs, inputs, ... }:
pkgs.buildNpmPackage (finalAttrs: {
  pname = "pi";
  version = "0.80.3";

  src = inputs.pi-src;

  patches = [
    ./patches/complete-pasted-skill-blocks-are-loaded.patch
  ];

  # No `npmWorkspace` — pi is `@earendil-works/pi-coding-agent` in the
  # monorepo and its dist resolves sibling workspaces via symlinks
  # under `node_modules/@earendil-works/pi-{ai,agent-core,tui,...}`. If
  # we point npmWorkspace at coding-agent only, the install hook
  # copies just that workspace, leaving every sibling-symlink dangling
  # at runtime. Install the whole monorepo and stitch in the `pi`
  # binary ourselves in postInstall.

  npmDepsHash = "sha256-geh8LH88OZybFXkR/jDeTdew6TNMdFM6jhCSYKn//dU=";

  makeCacheWritable = true;

  # `packages/ai`'s model refresh steps hit OpenRouter / ai-gateway.vercel /
  # models.dev to refresh catalogues that are also committed in the source.
  # Network is forbidden in the build sandbox, so the committed catalogues are
  # the source of truth at the pinned tag.
  postPatch = ''
    substituteInPlace packages/ai/package.json \
      --replace-fail '"generate-models": "node scripts/generate-models.ts"' \
                     '"generate-models": "true"' \
      --replace-fail '"generate-image-models": "node scripts/generate-image-models.ts"' \
                     '"generate-image-models": "true"'
  '';

  # pi's root `build` script sequences workspaces in dependency
  # order (tui → ai → agent → coding-agent → mom → web-ui → pods).
  # Building only the coding-agent workspace fails because the sibling
  # workspaces it imports from (`@mariozechner/pi-ai`, etc.) haven't
  # produced their dist/ yet. Run the root script instead of relying on
  # buildNpmPackage's default per-workspace build.
  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  # buildNpmPackage's default `npmInstallHook` is built around a
  # single-package shape (`npm pack` + extract); applied to the
  # monorepo root it drops the workspace dist/ artifacts. Skip it and
  # copy the entire build tree verbatim — we need the workspaces dir
  # plus node_modules so the symlinks inside `node_modules/@mariozechner/*`
  # resolve to real files at runtime.
  dontNpmInstall = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/pi-monorepo
    cp -r packages node_modules package.json $out/lib/pi-monorepo/

    mkdir -p $out/bin
    chmod +x $out/lib/pi-monorepo/packages/coding-agent/dist/cli.js
    makeWrapper "$out/lib/pi-monorepo/packages/coding-agent/dist/cli.js" "$out/bin/pi" \
      --run 'if [ -z "''${PI_PACKAGE_DIR:-}" ]; then export PI_PACKAGE_DIR="$HOME/.local/share/criomos/pi/package"; fi' \
      --run 'export LINKUP_API_KEY="''${LINKUP_API_KEY:-$(${pkgs.gopass}/bin/gopass show -o linkup.so/api-key 2>/dev/null || true)}"'

    runHook postInstall
  '';

  # `canvas` (transitive native node addon, comes via the workspace
  # tree even though pi-coding-agent itself doesn't use it directly)
  # builds with node-gyp against pkg-config-discovered system libs.
  nativeBuildInputs = with pkgs; [
    makeWrapper
    pkg-config
    python3
  ];
  buildInputs = with pkgs; [
    cairo
    pango
    libpng
    libjpeg
    librsvg
    pixman
  ];

  meta = {
    description = "pi — coding agent CLI from earendil-works/pi";
    homepage = "https://github.com/earendil-works/pi";
    license = pkgs.lib.licenses.mit;
    mainProgram = "pi";
  };
})
