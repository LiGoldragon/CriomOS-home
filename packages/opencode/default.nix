{ pkgs, ... }:
let inherit (pkgs) lib stdenvNoCC fetchurl; in
stdenvNoCC.mkDerivation (final: {
  pname = "opencode";
  version = "2.4.1";
  src = fetchurl (let
    sources = {
      x86_64-linux = { name = "opencode-linux-x64-baseline.tar.gz"; hash = "sha256-nd0Y4/r2Tq7M9qD8vJalx6FFIK5f1bYeW+UdiU9Hi0c="; };
      aarch64-linux = { name = "opencode-linux-arm64.tar.gz"; hash = "sha256-yyjPlFQa62KksupZl6mbXda65ZWncvNvvieSmfIDKk8="; };
    };
    source = sources.${stdenvNoCC.hostPlatform.system};
  in {
    inherit (source) hash;
    url = "https://github.com/anomalyco/opencode/releases/download/v${final.version}/${source.name}";
  });
  sourceRoot = ".";
  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode "$out/bin/opencode"
    wrapProgram "$out/bin/opencode" --prefix PATH : "${lib.makeBinPath [ pkgs.ripgrep ]}"
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
