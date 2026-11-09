# Flow Nexus 0.53.3, built per crate on the build base: its configured package
# and its clients under their versioned names (flow-0.53.3, flow-meta-0.53.3).
# It starts in its place (flow-nexus-place.nix): main, the place every flow
# reports to, whose sockets are $XDG_RUNTIME_DIR/nexus/main/ and whose memory
# is ~/.local/state/nexus/main/flow.sema. No unit runs it yet; its activation
# enables it, once the version at main has stopped (flows/ff3882/
# cutover-0533.md). The bare flow and flow-meta names stay on 0.53.1.
#
# It holds the stable hook: once its unit runs, ~/.local/bin/flow-hook is its
# flow-hook and its declared HarnessHook, so every Claude flow it launches
# runs that path, which the next version to hold it repoints.
#
# Being the version at main, it declares the user's Flow CLI configuration,
# ~/.config/nexus/flow.datom, `{ main }` (vision:nexus-v1): `flow '<datom>'`
# and `flow-meta '<datom>'` of 0.53.3 read their place from it, and no place
# is typed. The 0.53.1 clients read no configuration.
{ config, lib, ... }:
{
  imports = [
    (import ./flow-nexus-place.nix {
      version = "0.53.3";
      slug = "0533";
    })
  ];

  criomosHome.flow0533 = {
    enable = false;
    place = "main";
    stableHook = true;
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0533.datom";
    messageNexus = null;
  };

  home.packages = [ config.criomosHome.flow0533.clients ];

  xdg.configFile."nexus/flow.datom" = lib.mkIf (config.criomosHome.flow0533.place == "main") {
    source = "${config.criomosHome.flow0533.placeConfiguration}/nexus/flow.datom";
  };
}
