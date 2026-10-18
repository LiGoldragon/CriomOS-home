{ pkgs, ... }:
let
  manifest = builtins.fromJSON (builtins.readFile ../../owned-agents/codex/hashes.json);
  package = pkgs.callPackage ../../owned-agents/codex { };
  target = manifest.targets.${pkgs.stdenv.hostPlatform.system};
in
assert manifest.strategy == "prebuilt";
assert package.version == manifest.version;
assert package.releaseManifest == manifest;
assert builtins.elem target.cli.url (package.src.urls or [ package.src.url ]);
assert builtins.elem target.codeModeHost.url (
  package.codeModeHost.urls or [ package.codeModeHost.url ]
);
pkgs.runCommand "codex-consumed-release-manifest" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONPATH=${../../scripts}
  export PYTHONDONTWRITEBYTECODE=1
  python3 ${../../owned-agents/codex}/test_update.py
  test "$(${package}/bin/codex --version)" = "codex-cli ${manifest.version}"
  test -x ${package}/bin/codex-code-mode-host
  touch "$out"
''
