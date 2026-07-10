{ inputs, pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-subagents";
  version = "0.31.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-subagents
    mkdir -p \
      "$packageRoot" \
      "$packageRoot/.pi-deps/jiti" \
      "$packageRoot/.pi-deps/typebox" \
      "$packageRoot/.pi-deps/pi-tui" \
      "$packageRoot/.pi-deps/chalk" \
      "$packageRoot/.pi-deps/marked" \
      "$packageRoot/.pi-deps/mime-types" \
      "$packageRoot/.pi-deps/mime-types-types" \
      "$packageRoot/.pi-deps/get-east-asian-width" \
      "$packageRoot/.pi-deps/mime-db" \
      "$packageRoot/node_modules/@earendil-works" \
      "$packageRoot/node_modules/@types"

    tar -xzf ${inputs.pi-subagents-src} -C "$packageRoot" --strip-components=1
    tar -xzf ${inputs.pi-subagents-jiti-src} -C "$packageRoot/.pi-deps/jiti" --strip-components=1
    tar -xzf ${inputs.pi-subagents-typebox-src} -C "$packageRoot/.pi-deps/typebox" --strip-components=1
    tar -xzf ${inputs.pi-subagents-pi-tui-src} -C "$packageRoot/.pi-deps/pi-tui" --strip-components=1
    tar -xzf ${inputs.pi-subagents-chalk-src} -C "$packageRoot/.pi-deps/chalk" --strip-components=1
    tar -xzf ${inputs.pi-subagents-marked-src} -C "$packageRoot/.pi-deps/marked" --strip-components=1
    tar -xzf ${inputs.pi-subagents-mime-types-src} -C "$packageRoot/.pi-deps/mime-types" --strip-components=1
    tar -xzf ${inputs.pi-subagents-mime-types-types-src} -C "$packageRoot/.pi-deps/mime-types-types" --strip-components=1
    tar -xzf ${inputs.pi-subagents-get-east-asian-width-src} -C "$packageRoot/.pi-deps/get-east-asian-width" --strip-components=1
    tar -xzf ${inputs.pi-subagents-mime-db-src} -C "$packageRoot/.pi-deps/mime-db" --strip-components=1

    ln -s ../.pi-deps/jiti "$packageRoot/node_modules/jiti"
    ln -s ../.pi-deps/typebox "$packageRoot/node_modules/typebox"
    ln -s ../../.pi-deps/pi-tui "$packageRoot/node_modules/@earendil-works/pi-tui"
    ln -s ../.pi-deps/chalk "$packageRoot/node_modules/chalk"
    ln -s ../.pi-deps/marked "$packageRoot/node_modules/marked"
    ln -s ../.pi-deps/mime-types "$packageRoot/node_modules/mime-types"
    ln -s ../../.pi-deps/mime-types-types "$packageRoot/node_modules/@types/mime-types"
    ln -s ../.pi-deps/get-east-asian-width "$packageRoot/node_modules/get-east-asian-width"
    ln -s ../.pi-deps/mime-db "$packageRoot/node_modules/mime-db"

    patch -d "$packageRoot" -p1 < ${./agent-chain-clarify-opt-in.patch}
    patch -d "$packageRoot" -p1 < ${./slim-parent-skill.patch}
    patch -d "$packageRoot" -p1 < ${./detached-runner-peer-isolation.patch}
    patch -d "$packageRoot" -p1 < ${./async-runner-stderr.patch}
    patch -d "$packageRoot" -p1 < ${./stale-run-reconciliation.patch}
    patch -d "$packageRoot" -p1 < ${./full-child-extension-bridge.patch}
    patch -d "$packageRoot" -p1 < ${./acceptance-read-only-evidence.patch}

    runHook postInstall
  '';

  meta = {
    description = "Pi package for subagents, chains, parallel execution, and TUI clarification";
    homepage = "https://github.com/nicobailon/pi-subagents";
    license = pkgs.lib.licenses.mit;
  };
}
