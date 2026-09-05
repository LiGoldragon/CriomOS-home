{ pkgs, ... }:

let
  inherit (pkgs)
    lib
    stdenv
    fetchurl
    ;
  version = "0.27.12";
  asset =
    {
      x86_64-linux = {
        name = "x64";
        hash = "sha256-R5uicXyqLad+Lhiwo9YfQldHzl+mh7JBN4Qr1VV09m0=";
      };
      aarch64-linux = {
        name = "arm64";
        hash = "sha256-5gP6u+lFk4v06fwvAuwEEs9wZlhZ/+PKAUwiHIKqEBk=";
      };
    }
    .${stdenv.hostPlatform.system}
      or (throw "plannotator: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-linux-${asset.name}";
    inherit (asset) hash;
  };

  dontUnpack = true;
  # Bun's compiled executable keeps the application payload after the ELF data;
  # stripping it turns the executable back into the Bun runtime.
  dontStrip = true;
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc ];

  installPhase = ''
    install -Dm755 "$src" "$out/bin/plannotator"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/plannotator" --version >/dev/null
  '';

  meta = {
    description = "Visual plan and code review for coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    license = lib.licenses.mit;
    mainProgram = "plannotator";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
