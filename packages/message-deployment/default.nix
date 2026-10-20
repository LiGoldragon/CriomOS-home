{ pkgs, inputs, ... }:
let
  runtime = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
pkgs.runCommand "message-deployment" { passthru = { inherit runtime; }; } ''
  mkdir -p "$out/bin"
  for name in message message-meta message-nexus message-mcp-send; do
    test -x "${runtime}/bin/$name"
    ln -s "${runtime}/bin/$name" "$out/bin/$name"
  done
''
