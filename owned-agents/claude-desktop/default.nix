{
  pkgs,
  commandLineArgs ? "",
  claudeCodePackage ? pkgs.callPackage ../claude-code { },
}:

let
  inherit (pkgs)
    lib
    fetchurl
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
    copyDesktopItems
    makeWrapper
    patchelf
    pkgs.asar
    pkgs.nodejs
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
    # The 4.x claude-native binding links libpipewire-0.3 directly.
    pipewire
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

    asar extract "$out/lib/claude-desktop/resources/app.asar" "$TMPDIR/desktop-app"
    node - "$TMPDIR/desktop-app" "${claudeCodePackage}/bin/claude" "$out/lib/claude-desktop/resources/app.asar" "${pkgs.asar}/lib/node_modules/@electron/asar" <<'NODE'
    const fs = require("node:fs");
    const path = require("node:path");
    const asar = require(process.argv[5]);
    const archive = process.argv[4];
    const unpacked = () => asar.listPackage(archive).filter(name => asar.statFile(archive, name.slice(1), false).unpacked).sort();
    const originalUnpacked = unpacked();
    const root = process.argv[2];
    const binary = process.argv[3];
    const anchor = "this.localBinaryInitPromise=null";
    const build = path.join(root, ".vite", "build");
    const managers = fs.readdirSync(build).filter(name => name.endsWith(".js")).map(name => {
      const file = path.join(build, name);
      return {file, source: fs.readFileSync(file, "utf8")};
    }).filter(({source}) => source.includes(anchor));
    if (managers.length !== 1) throw new Error("Expected one Claude local binary manager");
    const [{file, source}] = managers;
    if (source.split(anchor).length !== 2) throw new Error("Claude manager initialization anchor changed");
    const call = "this.localBinaryInitPromise=this.initLocalBinary(" + JSON.stringify(binary) + ")";
    fs.writeFileSync(file, source.replace(anchor, call));
    const paths = originalUnpacked.map(name => path.join(root, name.slice(1)));
    const unpack = paths.length === 1 ? paths[0] : "{" + paths.join(",") + "}";
    asar.createPackageWithOptions(root, archive, {unpack}).then(() => {
      asar.uncache(archive);
      if (JSON.stringify(unpacked()) !== JSON.stringify(originalUnpacked)) throw new Error("vendor unpacked layout changed");
    }).catch(error => { console.error(error); process.exit(1); });
    NODE

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
