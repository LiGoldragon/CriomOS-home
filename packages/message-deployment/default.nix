{ pkgs, inputs, ... }:
let
  runtime = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;
  unit = pkgs.writeText "message-nexus.service" ''
    [Unit]
    Description=Message Nexus
    Requires=flow-nexus.service
    After=flow-nexus.service
    [Service]
    Type=simple
    Environment=HOME=%h
    Environment=XDG_RUNTIME_DIR=%t
    ExecStart=${runtime}/bin/message-nexus
    Restart=on-failure
    RestartSec=2
    [Install]
    WantedBy=default.target
  '';
in
pkgs.runCommand "message-deployment" { passthru = { inherit runtime unit; }; } ''
  mkdir -p "$out/bin" "$out/share/systemd/user"
  for name in message message-meta message-nexus message-mcp-send; do
    test -x "${runtime}/bin/$name"
    ln -s "${runtime}/bin/$name" "$out/bin/$name"
  done
  cp ${unit} "$out/share/systemd/user/message-nexus.service"
''
