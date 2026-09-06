{
  pkgs,
  # Blueprint auto-imports this expression as a standalone package. Runtime
  # Home consumers use the canonical factory's explicit object.
  claudeCodePackage ? pkgs.callPackage ../claude-code { },
  commandLineArgs ? "",
}:

let
  inherit (pkgs)
    lib
    fetchurl
    asar
    nodejs
    makeWrapper
    stdenvNoCC
    bintools
    copyDesktopItems
    makeDesktopItem
    patchelf
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gcc-unwrapped
    glib
    gtk3
    libdrm
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    libgbm
    nspr
    nss
    pango
    systemdLibs
    libglvnd
    libsecret
    libnotify
    libpulseaudio
    libayatana-appindicator
    libXcursor
    pipewire
    wayland
    xdg-utils
    libcap_ng
    libseccomp
    adwaita-icon-theme
    gsettings-desktop-schemas
    gnupg
    python3
    ;
  pname = "claude-desktop";
  mkUpdater = import ../../lib/mk-updater.nix { inherit lib; };
  formatelf = pkgs.callPackage ../../lib/formatelf.nix { };
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version urls hashes;
  platform = stdenvNoCC.hostPlatform.system;
  # The automatic formatelf hook is sourced from nativeBuildInputs.  This
  # follow-on hook must be sourced after it so its post-fixup action runs after
  # formatelf's RPATH normalization.
  claudeDesktopEglFixupHook =
    pkgs.makeSetupHook
      {
        name = "claude-desktop-egl-fixup-hook";
      }
      (
        pkgs.writeText "claude-desktop-egl-fixup-hook.sh" ''
          claudeDesktopEglFixup() {
            ${patchelf}/bin/patchelf --add-rpath ${libglvnd}/lib "$out/lib/claude-desktop/libGLESv2.so"
          }
          postFixupHooks+=(claudeDesktopEglFixup)
        ''
      );
  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "Claude";
    genericName = "AI Assistant";
    comment = "Desktop application for Claude.ai";
    exec = "claude-desktop %U";
    icon = "claude-desktop";
    keywords = [
      "AI"
      "Chat"
      "Assistant"
      "Claude"
      "Code"
      "LLM"
    ];
    categories = [
      "Utility"
      "Development"
    ];
    startupNotify = true;
    startupWMClass = "claude-desktop";
    singleMainWindow = true;
    mimeTypes = [ "x-scheme-handler/claude" ];
    actions = {
      NewChat = {
        name = "New chat";
        exec = "claude-desktop claude://claude.ai/new";
      };
      NewCode = {
        name = "New Claude Code session";
        exec = "claude-desktop claude://code/new";
      };
    };
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;
  src = fetchurl {
    url = urls.${platform} or (throw "Unsupported system: ${platform}");
    hash = hashes.${platform} or (throw "Unsupported system: ${platform}");
  };
  nativeBuildInputs = [
    formatelf
    asar
    nodejs
    copyDesktopItems
    makeWrapper
    patchelf
    claudeDesktopEglFixupHook
  ];
  buildInputs = [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk3
    libcap_ng
    libdrm
    libgbm
    libglvnd
    libX11
    libxcb
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    nspr
    nss
    pango
    libseccomp
    systemdLibs
  ];
  runtimeDependencies = [
    libayatana-appindicator
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    pipewire
    wayland
  ];
  desktopItems = [ desktopItem ];
  unpackPhase = ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar xf data.tar.xz
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/bin $out/share
    cp -a usr/lib/claude-desktop $out/lib/claude-desktop
    cp -a usr/share/icons $out/share/icons
    cp -a usr/share/doc $out/share/doc

    # The app's own local-binary selection is fail-closed and always points at
    # the one Claude Code derivation supplied to this package.
    app_asar="$out/lib/claude-desktop/resources/app.asar"
    unpacked_app="$out/lib/claude-desktop/resources/app.asar.unpacked"
    extracted_app="$TMPDIR/claude-desktop-app"
    # Native modules are dlopen'd from disk and cannot be read out of the
    # archive, so the repack reproduces this archive's own unpacked set.
    unpack_pattern="$(${nodejs}/bin/node ${./asar-unpack-pattern.mjs} "$app_asar")"
    ${asar}/bin/asar extract "$app_asar" "$extracted_app"
    ${nodejs}/bin/node ${./patch-runtime.mjs} "$extracted_app" ${claudeCodePackage}/bin/claude
    rm "$app_asar"
    rm -rf "$unpacked_app"
    ${asar}/bin/asar pack "$extracted_app" "$app_asar" --unpack "$unpack_pattern"

    # This is the sole launcher wrapper. It points directly at the unpacked
    # executable and therefore cannot retain an upstream store prefix.
    makeWrapper "$out/lib/claude-desktop/claude-desktop" "$out/bin/claude-desktop" \
      --prefix LD_LIBRARY_PATH : "$out/lib/claude-desktop" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs}

    runHook postInstall
  '';
  passthru = {
    category = "AI Coding Agents";
    declaredClaudeCode = claudeCodePackage;
    updater = mkUpdater {
      kind = "script";
      script = ./update.py;
      hashesFile = ./hashes.json;
    };
    updateScript = [
      (lib.getExe python3)
      ./update.py
      "--gpg"
      (lib.getExe' gnupg "gpg")
      "--gpgv"
      (lib.getExe' gnupg "gpgv")
      "--key"
      ./anthropic-archive-key.asc
    ];
  };
  meta = with lib; {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai";
    changelog = "https://claude.ai/download";
    license = licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "claude-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
