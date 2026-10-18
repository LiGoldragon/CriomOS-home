{
  lib,
  stdenvNoCC,
  fetchurl,
  ...
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./hashes.json);
  version = manifest.version;
  targets = manifest.targets;
  artifact = targets.${stdenvNoCC.hostPlatform.system};
in
assert manifest.strategy == "prebuilt";
stdenvNoCC.mkDerivation {
  pname = "codex";
  inherit version;
  src = fetchurl {
    inherit (artifact.cli) url hash;
  };
  codeModeHost = fetchurl {
    inherit (artifact.codeModeHost) url hash;
  };
  passthru.releaseManifest = manifest;
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 codex-${artifact.target} "$out/bin/codex"
    tar -xOzf "$codeModeHost" codex-code-mode-host-${artifact.target} > codex-code-mode-host
    install -Dm755 codex-code-mode-host "$out/bin/codex-code-mode-host"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    test "$("$out/bin/codex" --version)" = "codex-cli ${version}"
    test -x "$out/bin/codex-code-mode-host"
  '';
  meta = {
    description = "Locally promoted, reproducibly pinned Codex CLI";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames targets;
    mainProgram = "codex";
  };
}
