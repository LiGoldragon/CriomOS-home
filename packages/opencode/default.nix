{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation (final: {
  pname = "opencode";
  version = "1.19.6";
  src = fetchurl (let
    sources = {
      x86_64-linux = { name = "opencode-linux-x64-baseline-musl.tar.gz"; hash = "sha256-vGsNcCFj2FkWHujkPqPxbRvUOzBax84XdC6wG6ckifM="; };
      aarch64-linux = { name = "opencode-linux-arm64-musl.tar.gz"; hash = "sha256-RUBziHd9/BiUWRyXJ8Fp8gKtksdXVwOJUGMKD7sSypc="; };
    };
    source = sources.${stdenvNoCC.hostPlatform.system};
  in {
    inherit (source) hash;
    url = "https://github.com/anomalyco/opencode/releases/download/v${final.version}/${source.name}";
  });
  sourceRoot = ".";
  installPhase = ''
    runHook preInstall
    install -Dm755 opencode "$out/bin/opencode"
    runHook postInstall
  '';
  meta = {
    description = "OpenCode terminal coding agent";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
