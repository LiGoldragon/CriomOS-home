{
  lib,
  stdenvNoCC,
  fetchurl,
}:
{
  pname,
  version,
  targets,
  description,
  passthru ? { },
  meta ? { },
}:
let
  artifact = targets.${stdenvNoCC.hostPlatform.system};
  releaseUrl =
    binary:
    "https://github.com/openai/codex/releases/download/rust-v${version}/${binary}-${artifact.target}.tar.gz";
in
stdenvNoCC.mkDerivation {
  inherit pname version passthru;
  src = fetchurl {
    url = releaseUrl "codex";
    inherit (artifact) hash;
  };
  codeModeHost = fetchurl {
    url = releaseUrl "codex-code-mode-host";
    hash = artifact.hostHash;
  };
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
    inherit description;
    license = lib.licenses.asl20;
    platforms = builtins.attrNames targets;
    mainProgram = "codex";
  }
  // meta;
}
