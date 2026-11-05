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
  target =
    artifact.target or {
      x86_64-linux = "x86_64-unknown-linux-musl";
      aarch64-linux = "aarch64-unknown-linux-musl";
    }
    .${stdenvNoCC.hostPlatform.system};
  releaseUrl =
    binary:
    "https://github.com/openai/codex/releases/download/rust-v${version}/${binary}-${target}.tar.gz";
in
stdenvNoCC.mkDerivation {
  inherit pname version passthru;
  src = fetchurl {
    url = artifact.url or (releaseUrl "codex");
    inherit (artifact) hash;
  };
  codeModeHost = fetchurl {
    url = artifact.hostUrl or (releaseUrl "codex-code-mode-host");
    hash = artifact.hostHash;
  };
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 codex-${target} "$out/bin/codex"
    tar -xOzf "$codeModeHost" codex-code-mode-host-${target} > codex-code-mode-host
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
