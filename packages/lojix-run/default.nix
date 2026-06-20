{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lojix = inputs.lojix.packages.${system}.default;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "lojix-run";
  version = "0.3.10";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    substitute ${./lojix-run.py} "$out/bin/lojix-run" \
      --subst-var-by python ${pkgs.python3}/bin/python3 \
      --subst-var-by metaLojix ${lojix}/bin/meta-lojix \
      --subst-var-by ssh ${pkgs.openssh}/bin/ssh \
      --subst-var-by jj ${pkgs.jujutsu}/bin/jj
    chmod +x "$out/bin/lojix-run"
    ${pkgs.python3}/bin/python3 -m py_compile "$out/bin/lojix-run"

    runHook postInstall
  '';

  meta = {
    description = "CriomOS operator wrapper for lojix logs, redaction, exact refs, and postchecks";
    mainProgram = "lojix-run";
  };
}
