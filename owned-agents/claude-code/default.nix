{
  pkgs,
  inputs ? null,
  disableTelemetry ? false,
}:

let
  inherit (pkgs)
    lib
    stdenv
    makeWrapper
    versionCheckHook
    bubblewrap
    socat
    ;
  fetchurlTemplate = import ../../lib/fetchurl-template.nix {
    inherit (pkgs) fetchurl;
    interpolate = import ../../lib/interpolate.nix;
  };
  platformSource = import ../../lib/platform-source.nix {
    inherit stdenv fetchurlTemplate;
  };
  mkUpdater = import ../../lib/mk-updater.nix { inherit lib; };
  # wrap-buddy remains a generic, independently auto-discovered package.
  # This moved owned package reaches it through its canonical packages path.
  wrapBuddy = pkgs.callPackage ../../packages/wrap-buddy { };
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
    urlTemplate = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/{platform}/claude";
  };
in
stdenv.mkDerivation {
  pname = "claude-code";
  inherit (source) version src;
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.hostPlatform.isLinux [ wrapBuddy ];
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/claude
    runHook postInstall
  '';
  # The declared package disables mutable installation and update paths. The
  # optional telemetry switch is explicit so remote-control remains intact by
  # default.
  postFixup = ''
    wrapProgram $out/bin/claude \
      --argv0 claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
      ${lib.optionalString disableTelemetry "--set DISABLE_TELEMETRY 1 --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1"} \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      ${lib.optionalString stdenv.hostPlatform.isLinux "--prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          socat
        ]
      }"}
  '';
  __noChroot = stdenv.hostPlatform.isDarwin;
  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  passthru = {
    category = "AI Coding Agents";
    updater = mkUpdater {
      kind = "manifest-checksums";
      versionSource = {
        type = "text";
        url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/latest";
      };
      manifestUrl = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/{version}/manifest.json";
      checksumPath = "platforms.{platform}.checksum";
      platforms = source.updater.platforms;
      versionPolicy = "follow_pointer";
      script = ./update.py;
    };
    updateScript = [
      (lib.getExe pkgs.python3)
      ./update.py
    ];
  };
  meta = with lib; {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://claude.ai/code";
    changelog = "https://github.com/anthropics/claude-code/releases";
    license = licenses.unfree;
    maintainers = [
      maintainers.adeci
      maintainers.markus1189
      maintainers.mirkolenz
      maintainers.omarjatoi
      maintainers.oskarwires
      maintainers.xiaoxiangmoe
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "claude";
    platforms = source.platforms;
  };
}
