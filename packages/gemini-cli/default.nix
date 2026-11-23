{ lib, stdenvNoCC, fetchurl, nodejs_24, ripgrep, unzip, makeWrapper, writeText }:
stdenvNoCC.mkDerivation (final: {
  pname = "gemini-cli";
  version = "0.70.0";
  src = fetchurl {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${final.version}/gemini-cli-bundle.zip";
    hash = "sha256-bxEE9n2xt3HDMEDod13hFDJjo0JHQ8hgEjfmUb5SMPU=";
  };
  nativeBuildInputs = [ unzip makeWrapper ];
  sourceRoot = ".";
  installPhase = let
    systemSettings = writeText "gemini-system-settings.json" (builtins.toJSON {
      general = {
        enableAutoUpdate = false;
        enableAutoUpdateNotification = false;
      };
    });
  in ''
    runHook preInstall
    mkdir -p "$out/lib/gemini-cli" "$out/bin"
    cp -a . "$out/lib/gemini-cli"
    makeWrapper "${lib.getExe nodejs_24}" "$out/bin/gemini" \
      --add-flags "$out/lib/gemini-cli/gemini.js" \
      --set GEMINI_CLI_SYSTEM_SETTINGS_PATH "${systemSettings}" \
      --prefix PATH : "${lib.makeBinPath [ ripgrep ]}"
    runHook postInstall
  '';
  meta = {
    description = "Google Gemini terminal coding agent";
    homepage = "https://github.com/google-gemini/gemini-cli";
    license = lib.licenses.asl20;
    mainProgram = "gemini";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
