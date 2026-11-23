{ pkgs, ... }:
let inherit (pkgs) lib stdenvNoCC fetchurl; in
stdenvNoCC.mkDerivation (final: {
  pname = "opencode";
  version = "2.4.1";
  src = fetchurl (let
    sources = {
      x86_64-linux = { name = "opencode-linux-x64-baseline-musl.tar.gz"; hash = "sha256-PY0Lpm0z4WMevmG1U5zS75cack/2jrKGVUCTv1W6XJ8="; };
      aarch64-linux = { name = "opencode-linux-arm64-musl.tar.gz"; hash = "sha256-gU2S3GzhcqOCCQeX33Byt/4PKEDyRAg4IoGWeJwONS8="; };
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
