{ pkgs, ... }:
let inherit (pkgs) lib stdenvNoCC fetchurl; in
stdenvNoCC.mkDerivation (final: {
  pname = "opencode";
  version = "2.4.1";
  src = fetchurl (let
    sources = {
      x86_64-linux = { name = "cli-linux-x64-baseline"; hash = "sha512-hYF+w2CQU/Jx4Px2VNxHrfUybR6xze1FeOCmPXXsPWXWkk0BILJkxI0fQVA1FzlGPy6avHWJzzJ1fCf9wwkupw=="; };
      aarch64-linux = { name = "cli-linux-arm64"; hash = "sha512-olNKfoAuHaDtHrWrlqxh2RPSonSfAZPGJlru7tMNeNTlHyLSrTbDe/+HJ6vdYRp7g4yKLSQ8SG264U/IC7Pgtw=="; };
    };
    source = sources.${stdenvNoCC.hostPlatform.system};
  in {
    inherit (source) hash;
    url = "https://registry.npmjs.org/@opencode/${source.name}/-/${source.name}-${final.version}.tgz";
  });
  sourceRoot = "package";
  nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode "$out/bin/opencode"
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
