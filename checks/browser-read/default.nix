{ pkgs, inputs, ... }:
let
  fakeWrapper = pkgs.writeShellScriptBin "playwright-chrome" ''
    exec ${pkgs.python3}/bin/python3 ${./fake-wrapper.py} "$@"
  '';
  reader = pkgs.callPackage ../../packages/browser-read {
    inherit inputs;
    playwrightChrome = fakeWrapper;
  };
in
pkgs.runCommand "browser-read-synthetic" {
  nativeBuildInputs = [ pkgs.python3 pkgs.nodejs ];
  # Rust's single compile/test/lint and codec-currentness gate is included.
  rustChecks = reader.rustChecks;
} ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  node ${./page-test.cjs} ${../../packages/browser-read/read-page.cjs}
  python3 ${./test.py} ${reader}/bin/browser-read \
    ${../../packages/browser-read/session.py} ${fakeWrapper}/bin/playwright-chrome
  touch "$out"
''
