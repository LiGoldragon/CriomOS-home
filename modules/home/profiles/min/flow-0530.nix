# Flow Nexus 0.53.0 at its own place, beside 0.51.2: store
# ~/.local/state/flow-0530, sockets $XDG_RUNTIME_DIR/flow-0530. It is
# configured from its own mutable declaration file and its own Model-shaped
# configuration directory; the 0.51 Layer files stay as they are. It admits
# no Message Nexus. The bare flow and flow-meta names stay on 0.51.2 until
# 0.51 is stopped and retired.
{ config, ... }:
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
}
