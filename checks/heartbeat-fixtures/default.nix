{ pkgs, ... }:
pkgs.runCommand "core-heartbeat-fixtures" {
  nativeBuildInputs = [ pkgs.nodejs pkgs.util-linux ];
} ''
  cd ${../../packages/core-heartbeat/source}
  sha256sum -c SHA256SUMS
  node tools/heartbeat.test.mjs
  touch "$out"
''
