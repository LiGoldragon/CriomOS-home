{
  pkgs,
  codexPackage,
  codexDesktopGate,
}:

let
  inherit (pkgs)
    lib
    stdenv
    fetchurl
    coreutils
    dpkg
    makeWrapper
    python3
    wrapGAppsHook3
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libGL
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libsecret
    libusb1
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    systemd
    wayland
    xdg-utils
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    qt5
    qt6
    ;
  sourceData = builtins.fromJSON (builtins.readFile ./hashes.json);
  formatelf = pkgs.callPackage ../../lib/formatelf.nix { };
  platform = stdenv.hostPlatform.system;
  source = sourceData.sources.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "chatgpt-unwrapped";
  inherit (source) version;
  src = fetchurl { inherit (source) url hash; };
  dontStrip = true;
  dontWrapGApps = true;
  # The binary ships its own Qt5/Qt6 shims and receives explicit RPATH repair
  # below, so nixpkgs must not attempt a generic Qt wrapper.
  dontWrapQtApps = true;
  nativeBuildInputs = [
    formatelf
    dpkg
    makeWrapper
    python3
    wrapGAppsHook3
  ];
  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libGL
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libusb1
    libxkbcommon
    nspr
    nss
    pango
    pipewire
    stdenv.cc.cc.lib
    systemd
    wayland
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
    qt6.qtbase
  ];
  runtimeDependencies = [
    libGL
    libgbm
    libsecret
    pipewire
    wayland
    # The shipped application contains both Qt5 and Qt6 shims. Keep Qt5 in
    # the runtime closure and explicit RPATH below without activating a
    # second qtbase setup hook during the build.
    qt5.qtbase
  ];
  autoPatchelfIgnoreMissingDeps = [
    "libc++_shared.so"
    "libc.musl-x86_64.so.1"
    "liblog.so"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/lib" "$out/share"
    # Debian revisions have varied between a copied directory and links under
    # the Electron resource tree.  Require the documented application root,
    # retain its layout faithfully, then replace only the Codex executable
    # authority below.  Do not assume a pre-existing regular `resources/codex`.
    test -d usr/lib/chatgpt
    test -d usr/lib/chatgpt/resources
    test -x usr/lib/chatgpt/codex-launcher
    cp -a usr/lib/chatgpt "$out/lib/"
    cp -r usr/share/applications usr/share/pixmaps "$out/share/"
    ln -s ../lib/chatgpt/codex-launcher "$out/bin/chatgpt"
    # Keep the application-bypassing fallback on the canonical Codex binary.
    mkdir -p "$out/lib/chatgpt/resources"
    rm -f "$out/lib/chatgpt/resources/codex"
    if test -e "$out/lib/chatgpt/resources/codex"; then
      rm -rf "$out/lib/chatgpt/resources/codex"
    fi
    ln -s ${codexDesktopGate}/bin/codex "$out/lib/chatgpt/resources/codex"
    python3 ${./patch-asar.py} "$out/lib/chatgpt/resources/app.asar"
    wrapProgram "$out/lib/chatgpt/ChatGPT" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          xdg-utils
        ]
      }
    runHook postInstall
  '';
  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath [ qt5.qtbase ]} "$out/lib/chatgpt/libqt5_shim.so"
    patchelf --add-rpath ${lib.makeLibraryPath [ qt6.qtbase ]} "$out/lib/chatgpt/libqt6_shim.so"
  '';
  meta = with lib; {
    description = "Desktop application for ChatGPT and Codex";
    homepage = "https://developers.openai.com/codex/app";
    changelog = "https://learn.chatgpt.com/docs/changelog";
    license = licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "chatgpt";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
