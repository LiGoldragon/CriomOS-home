# Flow Nexus 0.53.0 at its own place, beside 0.51.2: store
# ~/.local/state/flow-0530, sockets $XDG_RUNTIME_DIR/flow-0530. It is
# configured from its own mutable declaration file and its own Model-shaped
# configuration directory; the 0.51 Layer files stay as they are. It admits
# no Message Nexus. It keeps the default send-server row, because 0.53
# reads the Codex app-servers for a flow-client Send from that row: with an
# empty list no Codex flow could send. No Message runs, so the row's MCP
# send server is never executed. The bare flow and flow-meta names point
# at it; 0.51 is retired.
{ config, ... }:
let
  cfg = config.criomosHome.flow0530;
in
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.53.0";
      slug = "0530";
    })
  ];

  criomosHome.flow0530 = {
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0530.datom";
    configurationDirectory = ./flow-nexus-config-0530;
    messageNexus = null;
  };

  home.file.".local/bin/flow".source = "${cfg.clients}/bin/flow-0.53.0";
  home.file.".local/bin/flow-meta".source = "${cfg.clients}/bin/flow-meta-0.53.0";
}
