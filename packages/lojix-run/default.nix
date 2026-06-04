{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lojixCli = inputs.lojix-cli.packages.${system}.default;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "lojix-run";
  version = "0.1.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    substitute ${./lojix-run.py} "$out/bin/lojix-run" \
      --subst-var-by python ${pkgs.python3}/bin/python3 \
      --subst-var-by lojix_cli ${lojixCli}/bin/lojix-cli \
      --subst-var-by ssh ${pkgs.openssh}/bin/ssh \
      --subst-var-by jj ${pkgs.jujutsu}/bin/jj
    chmod +x "$out/bin/lojix-run"
    ${pkgs.python3}/bin/python3 -m py_compile "$out/bin/lojix-run"

    runHook postInstall
  '';

  meta = {
    description = "CriomOS operator wrapper for lojix-cli logs, redaction, exact refs, and postchecks";
    mainProgram = "lojix-run";
  };
}
