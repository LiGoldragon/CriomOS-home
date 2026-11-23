{ pkgs, ... }:
let
  manifest = builtins.fromJSON (builtins.readFile ../../owned-agents/codex/hashes.json);
  package = pkgs.callPackage ../../owned-agents/codex { };
  target = manifest.targets.${pkgs.stdenv.hostPlatform.system};
in
assert package.version == manifest.version;
assert package.releaseManifest == manifest;
assert builtins.elem
  "https://github.com/openai/codex/releases/download/rust-v${manifest.version}/codex-package-${target.target}.tar.gz"
  (package.src.urls or [ package.src.url ]);
pkgs.runCommand "codex-consumed-release-manifest" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONPATH=${../../scripts}
  export PYTHONDONTWRITEBYTECODE=1
  python3 ${../../owned-agents/codex}/test_update.py
  test "$(${package}/bin/codex --version)" = "codex-cli ${manifest.version}"
  test -x ${package}/bin/codex-code-mode-host
  test -x ${package}/codex-resources/bwrap
  test -f ${package}/codex-package.json
  touch "$out"
''
