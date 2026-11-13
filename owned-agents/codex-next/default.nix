{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.171.0-alpha.2";
  targets = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-G8JlX9NrLr/Jp6DgcaKDJCbp5ldTpdbk1XgYz+A00Dc=";
      hostHash = "sha256-t2aImJBBJ9DwYiHKRkvdnL0aWWgNZKlHjCMlA4MC42k=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-tMd2ot6LvegNqjHICPI7l1mtEHanS1yCkUL+Rxa4POo=";
      hostHash = "sha256-GOZqA4ZTQA7kOIRCN9pZHONC9SS6CG+G6maD5EwHhXA=";
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
