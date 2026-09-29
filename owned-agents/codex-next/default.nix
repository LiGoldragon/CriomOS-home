{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.161.0-alpha.2";
  targets = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-Vfht8jbnRC2IwhWGfVMngXX85155T52yCpZ7ae5MqOk=";
      hostHash = "sha256-InR44u5W9CKTSx12FtmbUil7zTwA7v7rsS2c0QKmWyg=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-wmv0qdFeeKv7HuafcHQT8wfvN1UrSb+QmyVxcwgNIBE=";
      hostHash = "sha256-jg8pNsA8RchH+2lWq60fPPTxGwtZt6YIMOFxJG5xj18=";
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
