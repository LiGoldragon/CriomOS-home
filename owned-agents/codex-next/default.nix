{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.159.0-alpha.6";
  targets = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-gEu0dHBirNkojFpgh+Kr6mplzyJvLP5qp31XV+9LE0I=";
      hostHash = "sha256-0eAGHHFr0EoHbJ45NHU+IoNijCNcmRRL48I0p0dMhgw=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-k9aDxjp3Un8HeE+/Cso8phb6Olua+p/WpsNNYCZyq3s=";
      hostHash = "sha256-8NNTA6sUpTviDhKtrALJjv3srppVgeDuyOQcJvaF/yQ=";
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
