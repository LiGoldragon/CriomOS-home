{ lib, stdenvNoCC, fetchurl, jq, writeShellApplication }:
let
  manifest = builtins.fromJSON (builtins.readFile ./hashes.json);
  artifact = manifest.targets.${stdenvNoCC.hostPlatform.system};
  package = stdenvNoCC.mkDerivation {
    pname = "codex-plain";
    inherit (manifest) version;
    src = fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${manifest.version}/codex-package-${artifact.target}.tar.gz";
      inherit (artifact) hash;
    };
    sourceRoot = ".";
    nativeBuildInputs = [ jq ];
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a bin codex-package.json codex-path codex-resources "$out/"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/codex" --version)" = "codex-cli ${manifest.version}"
      jq -e '.layoutVersion == 1 and .version == "${manifest.version}" and .target == "${artifact.target}" and .entrypoint == "bin/codex" and .resourcesDir == "codex-resources" and .pathDir == "codex-path"' "$out/codex-package.json"
      test -x "$out/bin/codex-code-mode-host"
      test -x "$out/bin/codex-exec-server"
      test -x "$out/codex-path/rg"
      test -x "$out/codex-resources/bwrap"
      "$out/bin/codex" app-server --help > "$TMPDIR/app-server-help"
      "$out/bin/codex" app-server generate-json-schema --out "$TMPDIR/schema"
      test -n "$(find "$TMPDIR/schema" -name '*.json' -print -quit)"
    '';
    passthru.flowClient = writeShellApplication {
      name = "codex-plain-flow-client";
      text = ''
        : "''${CODEX_HOME:?Set CODEX_HOME to this endpoint's private home}"
        export CODEX_HOME
        exec ${package}/bin/codex "$@"
      '';
    };
    meta = {
      description = "Complete unpatched upstream stable Codex for a separate app-server endpoint";
      homepage = "https://github.com/openai/codex";
      license = lib.licenses.asl20;
      platforms = builtins.attrNames manifest.targets;
      mainProgram = "codex";
    };
  };
in package
