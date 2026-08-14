{
  inputs,
  pkgs,
  codexCliPackage ? inputs.codex-cli.packages.${pkgs.stdenv.hostPlatform.system}.default,
  sharedAppServerSocket ? null,
  ...
}:
# Blueprint evaluates package outputs for every exposed system. Avoid resolving
# the local Agent Intercom family's Linux inputs on unsupported systems.
if
  !(builtins.elem pkgs.stdenv.hostPlatform.system [
    "x86_64-linux"
    "aarch64-linux"
  ])
then
  null
else
  let
    system = pkgs.stdenv.hostPlatform.system;
    claudeCodePackage = pkgs.callPackage ../claude-code { inherit inputs; };
    esbuildCompanion =
      {
        x86_64-linux = {
          packageName = "linux-x64";
          src = inputs.agent-intercom-esbuild-linux-x64-src;
        };
        aarch64-linux = {
          packageName = "linux-arm64";
          src = inputs.agent-intercom-esbuild-linux-arm64-src;
        };
      }
      .${system};

    agentIntercomCore = pkgs.buildNpmPackage {
      pname = "agent-intercom-core";
      version = "0.1.0";
      src = inputs.agent-intercom-core-src;
      npmDepsHash = "sha256-WM4rUbND4l/2kDZDeZY2rDDp2QsYGXy+I2Uf6Bnc6MA=";
      npmDepsFetcherVersion = 2;
      dontNpmInstall = true;

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -R dist package.json "$out/"
        runHook postInstall
      '';
    };

    installTsxRuntime = packageRoot: ''
      mkdir -p \
        "${packageRoot}/.pi-deps/tsx" \
        "${packageRoot}/.pi-deps/typebox" \
        "${packageRoot}/.pi-deps/esbuild" \
        "${packageRoot}/.pi-deps/esbuild-${esbuildCompanion.packageName}" \
        "${packageRoot}/.pi-deps/get-tsconfig" \
        "${packageRoot}/.pi-deps/resolve-pkg-maps" \
        "${packageRoot}/node_modules/@dataforxyz" \
        "${packageRoot}/node_modules/@esbuild"

      tar -xzf ${inputs.agent-intercom-tsx-src} -C "${packageRoot}/.pi-deps/tsx" --strip-components=1
      tar -xzf ${inputs.agent-intercom-typebox-src} -C "${packageRoot}/.pi-deps/typebox" --strip-components=1
      tar -xzf ${inputs.agent-intercom-esbuild-src} -C "${packageRoot}/.pi-deps/esbuild" --strip-components=1
      tar -xzf ${esbuildCompanion.src} -C "${packageRoot}/.pi-deps/esbuild-${esbuildCompanion.packageName}" --strip-components=1
      tar -xzf ${inputs.agent-intercom-get-tsconfig-src} -C "${packageRoot}/.pi-deps/get-tsconfig" --strip-components=1
      tar -xzf ${inputs.agent-intercom-resolve-pkg-maps-src} -C "${packageRoot}/.pi-deps/resolve-pkg-maps" --strip-components=1

      ln -s ../.pi-deps/tsx "${packageRoot}/node_modules/tsx"
      ln -s ../.pi-deps/typebox "${packageRoot}/node_modules/typebox"
      ln -s ../.pi-deps/esbuild "${packageRoot}/node_modules/esbuild"
      ln -s ../.pi-deps/get-tsconfig "${packageRoot}/node_modules/get-tsconfig"
      ln -s ../.pi-deps/resolve-pkg-maps "${packageRoot}/node_modules/resolve-pkg-maps"
      ln -s ../../.pi-deps/esbuild-${esbuildCompanion.packageName} "${packageRoot}/node_modules/@esbuild/${esbuildCompanion.packageName}"
      cp -R ${agentIntercomCore}/. "${packageRoot}/node_modules/@dataforxyz/agent-intercom-core"
    '';

    sharedAppServerWrapperHook =
      if sharedAppServerSocket == null then
        ""
      else
        ''
          --run 'export CODEX_INTERCOM_APP_SERVER_SOCKET="${sharedAppServerSocket}"'
        '';
  in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "agent-intercom";
    version = "0.10.0";
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.makeWrapper
      pkgs.nodejs
      pkgs.patch
    ];

    installPhase = ''
      runHook preInstall

      root="$out/share/agent-intercom"
      mkdir -p "$root"

      cp -R ${inputs.agent-intercom-pi-src}/. "$root/pi"
      cp -R ${inputs.agent-intercom-orchestrator-src}/. "$root/orchestrator"
      cp -R ${inputs.agent-intercom-codex-src}/. "$root/codex"
      cp -R ${inputs.agent-intercom-opencode-src}/. "$root/opencode"
      chmod -R u+w "$root/pi" "$root/orchestrator" "$root/codex" "$root/opencode"

      ${installTsxRuntime "$root/pi"}
      ${installTsxRuntime "$root/orchestrator"}
      ${installTsxRuntime "$root/codex"}
      patch --directory "$root/codex" --strip=1 --input ${./coi-shared-app-server.patch}
      (cd "$root/codex" && ${pkgs.nodejs}/bin/node scripts/build.mjs)

      claudeBuild="$TMPDIR/claude"
      cp -R ${inputs.agent-intercom-claude-src}/. "$claudeBuild"
      chmod -R u+w "$claudeBuild"
      mkdir -p \
        "$claudeBuild/node_modules/@dataforxyz" \
        "$claudeBuild/node_modules/@esbuild/${esbuildCompanion.packageName}" \
        "$claudeBuild/node_modules/esbuild"
      cp -R ${agentIntercomCore}/. "$claudeBuild/node_modules/@dataforxyz/agent-intercom-core"
      tar -xzf ${inputs.agent-intercom-esbuild-src} -C "$claudeBuild/node_modules/esbuild" --strip-components=1
      tar -xzf ${esbuildCompanion.src} -C "$claudeBuild/node_modules/@esbuild/${esbuildCompanion.packageName}" --strip-components=1
      (cd "$claudeBuild" && ${pkgs.nodejs}/bin/node scripts/build.mjs)
      cp -R "$claudeBuild/dist" "$root/claude"

      mkdir -p "$out/bin"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/codex-intercom-mcp" \
        --add-flags "$root/codex/dist/codex-server.mjs"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/codex-intercom-bridge" \
        --add-flags "$root/codex/dist/bridge-daemon.mjs"
      # `coi` starts a local server on non-graphical profiles. A graphical
      # profile supplies a shared Desktop-owned socket, so the bridge attaches
      # instead. Its child command always remains the upstream raw CLI, never
      # this package's normal `codex` alias.
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/coi" \
        --add-flags "$root/codex/dist/coi.mjs --yolo" \
        --set CODEX_INTERCOM_CODEX_COMMAND ${codexCliPackage}/bin/codex \
        ${sharedAppServerWrapperHook}
      makeWrapper "$out/bin/coi" "$out/bin/codex"
      makeWrapper ${codexCliPackage}/bin/codex "$out/bin/codex-raw"

      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/claude-intercom-mcp" \
        --add-flags "$root/claude/claude-server.mjs"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/claude-intercom-worker" \
        --add-flags "$root/claude/worker-daemon.mjs" \
        --set CLAUDE_INTERCOM_CLAUDE_COMMAND ${claudeCodePackage}/bin/claude
      # `cci` is the normal wakeable Claude bridge. Its own child process is
      # the upstream raw CLI, while normal `claude` remains only an alias.
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/cci" \
        --add-flags "$root/claude/cci.mjs --dangerously-skip-permissions" \
        --set CLAUDE_INTERCOM_CLAUDE_COMMAND ${claudeCodePackage}/bin/claude
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/ccim" \
        --add-flags "$root/claude/ccim.mjs" \
        --set CLAUDE_INTERCOM_CLAUDE_COMMAND ${claudeCodePackage}/bin/claude
      makeWrapper "$out/bin/cci" "$out/bin/claude"
      makeWrapper ${claudeCodePackage}/bin/claude "$out/bin/claude-raw"

      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/agent-intercom-fleet" \
        --add-flags "--experimental-strip-types $root/orchestrator/src/agent-fleet-cli.mjs"
      makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/agent-intercom-fleet-cleanup" \
        --add-flags "--experimental-strip-types $root/orchestrator/src/agent-fleet-cleanup.mjs"

      runHook postInstall
    '';

    meta = {
      description = "Pinned local-only Agent Intercom adapters and orchestrator";
      homepage = "https://github.com/dataforxyz/agent-intercom-pi";
      license = pkgs.lib.licenses.agpl3Plus;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
