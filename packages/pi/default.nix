{ pkgs, inputs, ... }:
pkgs.buildNpmPackage (finalAttrs: {
  pname = "pi";
  version = "0.70.6";

  src = inputs.pi-src;

  # No `npmWorkspace` — pi is `@mariozechner/pi-coding-agent` in the
  # monorepo and its dist resolves sibling workspaces via symlinks
  # under `node_modules/@mariozechner/pi-{ai,agent-core,tui,...}`. If
  # we point npmWorkspace at coding-agent only, the install hook
  # copies just that workspace, leaving every sibling-symlink dangling
  # at runtime. Install the whole monorepo and stitch in the `pi`
  # binary ourselves in postInstall.

  npmDepsHash = "sha256-pEVIqp9rbuHFE6eqSmADmIXWAPey1VbD7qmOJwksz1o=";

  makeCacheWritable = true;

  # `packages/ai`'s `generate-models` step (run as part of its build
  # script) hits openrouter / ai-gateway.vercel / models.dev to refresh
  # the catalogue that's also committed at `src/models.generated.ts`.
  # Network is forbidden in the build sandbox, so the refresh either
  # fails or returns empty and clobbers the committed file, leaving
  # `src/models.ts` (which imports it as `MODELS`) typed too narrowly
  # for tsgo to compile. Stub the refresh; the committed catalogue is
  # the source of truth at the pinned tag anyway.
  postPatch = ''
    substituteInPlace packages/ai/package.json \
      --replace-fail '"generate-models": "npx tsx scripts/generate-models.ts"' \
                     '"generate-models": "true"'
  '';

  # pi-mono's root `build` script sequences workspaces in dependency
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
    ln -s $out/lib/pi-monorepo/packages/coding-agent/dist/cli.js $out/bin/pi

    runHook postInstall
  '';

  # `canvas` (transitive native node addon, comes via the workspace
  # tree even though pi-coding-agent itself doesn't use it directly)
  # builds with node-gyp against pkg-config-discovered system libs.
  nativeBuildInputs = with pkgs; [
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
    description = "pi — coding agent CLI from badlogic/pi-mono";
    homepage = "https://github.com/badlogic/pi-mono";
    license = pkgs.lib.licenses.mit;
    mainProgram = "pi";
  };
})
