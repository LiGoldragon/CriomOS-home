{ pkgs, ... }:

let
  inherit (pkgs) lib;

  disabledLanguageFeatureExtensions = [
    # Manual/mutable installs of the Rust Analyzer extension must not
    # start a rust-analyzer server from casual Codium windows.
    "rust-lang.rust-analyzer"

    # Built into VSCodium. The Markdown preview remains available; this
    # is only the JavaScript/TypeScript language-service extension.
    "vscode.typescript-language-features"
  ];

  disableLanguageFeatureFlags = lib.escapeShellArgs (
    lib.concatMap (extension: [
      "--disable-extension"
      extension
    ]) disabledLanguageFeatureExtensions
  );
in
pkgs.symlinkJoin {
  name = "vscodium-casual";
  paths = [ pkgs.vscodium ];
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
    wrapProgram "$out/bin/codium" \
      --add-flags ${lib.escapeShellArg disableLanguageFeatureFlags}
  '';

  passthru = {
    inherit disabledLanguageFeatureExtensions;
  };
}
