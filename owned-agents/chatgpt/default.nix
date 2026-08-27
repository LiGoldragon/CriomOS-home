{
  pkgs,
  # Blueprint auto-imports this expression as a standalone package. Runtime
  # Home consumers use the canonical factory's explicit object.
  codexPackage ? pkgs.callPackage ../codex { },
  codexDesktopGate ? pkgs.callPackage ../codex/desktop-gate.nix {
    codexCliPackage = codexPackage;
  },
  chatgpt-unwrapped ? pkgs.callPackage ./unwrapped.nix { inherit codexPackage codexDesktopGate; },
  commandLineArgs ? "",
}:

let
  inherit (pkgs)
    lib
    stdenvNoCC
    makeShellWrapper
    gnupg
    python3
    ;
  mkUpdater = import ../../lib/mk-updater.nix { inherit lib; };
in
stdenvNoCC.mkDerivation {
  pname = "chatgpt";
  inherit (chatgpt-unwrapped) version;
  dontUnpack = true;
  nativeBuildInputs = [ makeShellWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    makeShellWrapper ${chatgpt-unwrapped}/bin/chatgpt "$out/bin/chatgpt" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland}}" \
      --add-flags ${lib.escapeShellArg commandLineArgs} \
      --set CODEX_APP_SERVER_USE_LOCAL_DAEMON 1 \
      --unset CODEX_CLI_PATH \
      --unset CODEX_APP_SERVER_FORCE_CLI \
      --unset CODEX_APP_SERVER_CLI_COMMAND
    ln -s ${chatgpt-unwrapped}/share "$out/share"
    runHook postInstall
  '';
  passthru = {
    category = "AI Coding Agents";
    inherit codexPackage;
    inherit codexDesktopGate;
    unwrapped = chatgpt-unwrapped;
    inherit commandLineArgs;
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
      ./openai-archive-key.asc
    ];
  };
  meta = (chatgpt-unwrapped.meta or { }) // {
    maintainers = [ lib.maintainers.wattmto ];
  };
}
