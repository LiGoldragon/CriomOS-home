{ pkgs, ... }:

let
  inherit (pkgs) lib;

  pname = "traycer";
  version = "1.1.4";

  src = pkgs.fetchurl {
    url = "https://github.com/traycerai/traycer/releases/download/desktop-v${version}/traycer-desktop-linux-x86_64.AppImage";
    hash = "sha256-8vi/E3MYKh5vDRG9vh7AKKNfNI7VZHlqbqJO6jXP5Yc=";
  };

  appimageContents = pkgs.appimageTools.extractType2 {
    inherit pname version src;
  };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/traycer-desktop.desktop \
      "$out/share/applications/traycer.desktop"
    substituteInPlace "$out/share/applications/traycer.desktop" \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=traycer --no-sandbox %U'

    if [ -d ${appimageContents}/usr/share/icons ]; then
      cp -r ${appimageContents}/usr/share/icons "$out/share/"
    fi
  '';

  meta = {
    description = "AI coding assistant desktop shell";
    homepage = "https://traycer.ai";
    license = lib.licenses.asl20;
    mainProgram = "traycer";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
