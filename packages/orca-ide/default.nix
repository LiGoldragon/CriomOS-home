{ pkgs, ... }:
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (packages: [ packages.pygobject3 ]);
in
pkgs.stdenvNoCC.mkDerivation (final: {
  pname = "orca-ide";
  version = "1.4.272";
  src = pkgs.fetchurl (
    let
      sources = {
        x86_64-linux = { debArchitecture = "amd64"; hash = "sha256-GtSIQbZ9JfdUry+lFjUUgXCdK0SBx0YIazNMoe8GnOE="; };
        aarch64-linux = { debArchitecture = "arm64"; hash = "sha256-Oel1iOYwfFDAhKbVJ9PiakbcAzA94sVq7jtMdXqV+nI="; };
      };
      source = sources.${pkgs.stdenv.hostPlatform.system};
    in {
      inherit (source) hash;
      url = "https://github.com/stablyai/orca/releases/download/v${final.version}/orca-ide_${final.version}_${source.debArchitecture}.deb";
    }
  );
  nativeBuildInputs = with pkgs; [ autoPatchelfHook dpkg makeWrapper ];
  buildInputs = with pkgs; [
    alsa-lib at-spi2-core cairo cups dbus expat glib gtk3 libdrm libgbm
    libnotify libsecret libuuid libxkbcommon libx11 libxcb libxcomposite
    libxdamage libxext libxfixes libxrandr libxscrnsaver libxtst nspr nss
    pango stdenv.cc.cc.lib systemdLibs
  ];
  runtimeDependencies = with pkgs; [ gtk3 libsecret ];
  # The remote deployment template is a byte payload for machines that may
  # use a different libc or architecture. Fix up the local desktop and CLI
  # only; put back the unmodified payload after the local fixup.
  dontAutoPatchelf = true;
  sourceRoot = ".";
  unpackPhase = "dpkg-deb -x $src .";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib" "$out/bin" "$out/share"
    cp -a opt/Orca "$out/lib/orca"
    # Programs for the desktop vendor's other platforms aren't used on Linux.
    rm -r "$out/lib/orca/resources/app.asar.unpacked/resources/darwin"
    cp -a usr/share/{applications,icons} "$out/share/"
    substituteInPlace "$out/share/applications/orca-ide.desktop" \
      --replace-fail "Exec=/opt/Orca/orca-ide %U" "Exec=$out/bin/orca-ide-gui %U"
    app="$out/lib/orca/orca-ide"
    cli="$out/lib/orca/resources/app.asar.unpacked/out/cli/index.js"
    test -f "$cli"
    makeWrapper "$app" "$out/bin/orca-ide-gui" \
      --prefix PATH : "${lib.makeBinPath (with pkgs; [ at-spi2-core xclip xdotool xorg.xvfb xdg-utils python ])}"
    makeWrapper "$app" "$out/bin/orca-ide" \
      --run 'export ORCA_NODE_OPTIONS="''${NODE_OPTIONS-}" ORCA_NODE_REPL_EXTERNAL_MODULE="''${NODE_REPL_EXTERNAL_MODULE-}"' \
      --unset NODE_OPTIONS --unset NODE_REPL_EXTERNAL_MODULE \
      --set ELECTRON_RUN_AS_NODE 1 --add-flags "$cli"
    vendorResources="$out/lib/orca/resources"
    mv "$vendorResources/orcad-template" "$TMPDIR/orca-remote-template"
    find "$vendorResources/node_modules/@koromix" -type d -name 'musl_*' -print > "$TMPDIR/orca-musl-paths"
    mkdir "$TMPDIR/orca-musl"
    while IFS= read -r module; do
      mv "$module" "$TMPDIR/orca-musl/''${module##*/}"
    done < "$TMPDIR/orca-musl-paths"
    runHook postInstall
  '';
  postFixup = ''
    autoPatchelf "$out"
    mv "$TMPDIR/orca-remote-template" "$out/lib/orca/resources/orcad-template"
    while IFS= read -r module; do
      mv "$TMPDIR/orca-musl/''${module##*/}" "$module"
    done < "$TMPDIR/orca-musl-paths"
  '';
  meta = {
    description = "Orca multi-agent development environment";
    homepage = "https://github.com/stablyai/orca";
    license = lib.licenses.mit;
    mainProgram = "orca-ide";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
