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
  nativeBuildInputs = [ pkgs.makeWrapper ];
  # Bun's single-file release includes a payload at the end of the executable.
  # Preserve the published bytes and select the host's ELF loader in the wrapper.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/opencode "$out/libexec/opencode"
    makeWrapper "${pkgs.stdenv.cc.bintools.dynamicLinker}" "$out/bin/opencode" \
      --add-flags "$out/libexec/opencode" \
      --prefix PATH : "${lib.makeBinPath [ pkgs.ripgrep ]}"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    cd "$HOME"
    "$out/bin/opencode" --version | grep -F "opencode v${final.version}"
  '';
  meta = {
    description = "OpenCode terminal coding agent";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
