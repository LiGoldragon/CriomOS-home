{ pkgs, ... }:
let
  inherit (pkgs) lib appimageTools fetchurl python3 stdenv;
  pname = "orca-ide";
  version = "1.4.272";
  sources = {
    x86_64-linux = { name = "orca-linux.AppImage"; hash = "sha256-OfiJ29GxEYKRcsaWN0cqRiQeRZEGRxmjDHmwE4tbHWo="; };
    aarch64-linux = { name = "orca-linux-arm64.AppImage"; hash = "sha256-PAj36D9t3KQKWi91oLeDJIBlMpiexatARE3A4nocX6M="; };
  };
  source = sources.${stdenv.hostPlatform.system};
  src = fetchurl {
    inherit (source) hash;
    url = "https://github.com/stablyai/orca/releases/download/v${version}/${source.name}";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
  python = python3.withPackages (packages: [ packages.pygobject3 ]);
in
appimageTools.wrapType2 {
  inherit pname version src;
  extraPkgs = pkgs: [ pkgs.at-spi2-core pkgs.xclip pkgs.xdotool pkgs.xvfb python ];
  extraInstallCommands = ''
    mv "$out/bin/orca-ide" "$out/bin/orca-ide-gui"
    cli="${contents}/resources/app.asar.unpacked/out/cli/index.js"
    test -f "$cli"
    cat > "$out/bin/orca-ide" <<'EOF'
    #!${stdenv.shell}
    set -eu
    script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    export ORCA_NODE_OPTIONS="''${NODE_OPTIONS-}"
    export ORCA_NODE_REPL_EXTERNAL_MODULE="''${NODE_REPL_EXTERNAL_MODULE-}"
    unset NODE_OPTIONS NODE_REPL_EXTERNAL_MODULE
    ELECTRON_RUN_AS_NODE=1 exec "$script_dir/orca-ide-gui" \
      "${contents}/resources/app.asar.unpacked/out/cli/index.js" "$@"
    EOF
    chmod 755 "$out/bin/orca-ide"
    install -Dm444 "${contents}/orca-ide.desktop" "$out/share/applications/orca-ide.desktop"
    substituteInPlace "$out/share/applications/orca-ide.desktop" \
      --replace-fail "Exec=AppRun --no-sandbox %U" "Exec=orca-ide-gui --no-sandbox %U"
    cp -r "${contents}/usr/share/icons" "$out/share/"
  '';
  meta = {
    description = "Orca multi-agent development environment";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    mainProgram = "orca-ide";
    platforms = builtins.attrNames sources;
  };
}
