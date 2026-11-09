# Flow Nexus 0.53.3, built per crate on the build base: its configured package
# and its clients under their versioned names (flow-0.53.3, flow-meta-0.53.3).
# No unit runs it yet; its store, sockets and configuration come with its
# activation. The bare flow and flow-meta names stay on 0.53.1.
#
# It holds the stable hook: once its unit runs, ~/.local/bin/flow-hook is its
# flow-hook, and every Claude flow it launches runs that path, which the next
# version to hold it repoints.
#
# Its Nexus announces readiness (READY=1 once both sockets are bound), so its
# unit is Type=notify: a unit ordered after it finds both sockets listening.
{ config, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.53.3";
      slug = "0533";
    })
  ];

  criomosHome.flow0533 = {
    enable = false;
    stableHook = true;
    notifiesReadiness = true;
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0533.datom";
    messageNexus = null;
  };

  home.packages = [ config.criomosHome.flow0533.clients ];
}
