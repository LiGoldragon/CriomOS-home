{ pkgs, ... }:

let
  inherit (pkgs) lib;

  pname = "traycer";
  version = "1.1.4";

  src = pkgs.fetchurl {
    url = "https://github.com/traycerai/traycer/releases/download/desktop-v${version}/traycer-desktop-linux-x86_64.AppImage";
    hash = "sha256-8vi/E3MYKh5vDRG9vh7AKKNfNI7VZHlqbqJO6jXP5Yc=";
  };

  rawAppimageContents = pkgs.appimageTools.extractType2 {
    inherit pname version src;
  };

  traycerCliFhs = pkgs.buildFHSEnv {
    pname = "traycer-cli-linux-compat";
    inherit version;

    targetPkgs = pkgs: pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs pkgs;
    multiPkgs = pkgs: pkgs.appimageTools.defaultFhsEnvArgs.multiPkgs pkgs;
    runScript = "${rawAppimageContents}/resources/cli/linux-x64/traycer";
  };

  appimageContents =
    pkgs.runCommand "${pname}-${version}-nix-extracted"
      {
        nativeBuildInputs = [ pkgs.asar ];
      }
      ''
        cp -a ${rawAppimageContents} "$out"
        chmod -R u+w "$out"

        # Upstream attaches an Electron application menu to each Linux window.
        # Keep the menu and accelerators available but hide the native menu bar by
        # default so the packaged desktop window does not show a top menu strip.
        appAsar="$out/resources/app.asar"
        mainBundle="app-asar/dist/main/index.js"
        asar extract "$appAsar" app-asar
        substituteInPlace "$mainBundle" \
          --replace-fail \
            '    titleBarStyle: isMac ? "hiddenInset" : isWindows ? "hidden" : "default",' \
            $'    titleBarStyle: isMac ? "hiddenInset" : isWindows ? "hidden" : "default",\n    autoHideMenuBar: true,' \
          --replace-fail \
            '        record2.window.setMenu(menu);' \
            $'        record2.window.setMenu(menu);\n        record2.window.setAutoHideMenuBar(true);'
        grep -Fq '    autoHideMenuBar: true,' "$mainBundle"
        grep -Fq '        record2.window.setAutoHideMenuBar(true);' "$mainBundle"
        asar pack --unpack-dir node_modules/font-list app-asar "$appAsar"
        test -d "$out/resources/app.asar.unpacked/node_modules/font-list"
        rm -rf app-asar

        cliDir="$out/resources/cli/linux-x64"
        test -x "$cliDir/traycer"
        mv "$cliDir/traycer" "$cliDir/traycer-unwrapped"
        printf '%s\n' \
          '#!${pkgs.runtimeShell}' \
          'exec ${traycerCliFhs}/bin/traycer-cli-linux-compat "$@"' \
          > "$cliDir/traycer"
        chmod 755 "$cliDir/traycer"
      '';
in
pkgs.appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;

  extraPreBwrapCmds = ''
    traycer_cli_manifest="''${HOME:-}/.traycer/cli/manifest.json"
    traycer_cli_link="''${HOME:-}/.traycer/cli/bin/traycer"
    traycer_cli_target="${appimageContents}/resources/cli/linux-x64/traycer"
    if [ -n "''${HOME:-}" ] \
      && [ -f "$traycer_cli_manifest" ] \
      && [ -L "$traycer_cli_link" ] \
      && grep -q '"source"[[:space:]]*:[[:space:]]*"desktop"' "$traycer_cli_manifest"; then
      current_target="$(readlink "$traycer_cli_link" || true)"
      if [ "$current_target" != "$traycer_cli_target" ]; then
        ln -sfn "$traycer_cli_target" "$traycer_cli_link"
      fi
    fi
  '';

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
