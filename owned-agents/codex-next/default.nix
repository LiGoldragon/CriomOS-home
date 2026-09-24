{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.158.0-alpha.9";
  targets = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-r6jIHXWayHDyGbTKysFbpa1qERB7W3sQXI2Cg7jRFnw=";
      hostHash = "sha256-CqTxMWD+Y4QmGMt8JHTw7bKNaN8lKiPWPuh0u0apP1Q=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-e202MgQU0Atua8WVlJJ/rIYksCL6j9hNMw3zOoYqPxA=";
      hostHash = "sha256-b77gtc0Hn8RGplFvIaCIs5+o7keUbfE+Hn+dH+AT+88=";
    };
  };
  artifact = targets.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "codex-next";
  inherit version;
  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${artifact.target}.tar.gz";
    inherit (artifact) hash;
  };
  codeModeHost = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${artifact.target}.tar.gz";
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
    description = "Pinned upstream Codex candidate for the isolated next server";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames targets;
    mainProgram = "codex";
  };
}
