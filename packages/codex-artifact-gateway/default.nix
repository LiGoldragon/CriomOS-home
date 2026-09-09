{ pkgs, ... }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "codex-artifact-gateway";
  version = "1.0.0";
  src = ./.;
  dontBuild = true;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = ''
    runHook preInstall
    install -Dm755 gateway.py "$out/libexec/codex-artifact-gateway/gateway.py"
    makeWrapper ${pkgs.lib.getExe pkgs.python3} "$out/bin/codex-artifact-gateway" \
      --add-flags "$out/libexec/codex-artifact-gateway/gateway.py"
    runHook postInstall
  '';
  meta = {
    description = "TLS Tailnet gateway for capability-authorized artifacts";
    license = pkgs.lib.licenses.mit;
    mainProgram = "codex-artifact-gateway";
    platforms = pkgs.lib.platforms.unix;
  };
}
