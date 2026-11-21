# Flow Nexus 0.55.0, built per crate on the build base: its package
# and its clients under their versioned names (flow-0.55.0,
# flow-meta-0.55.0). It starts in its place (flow-nexus-place.nix):
# main, the place every flow reports to, whose sockets are
# $XDG_RUNTIME_DIR/nexus/main/ and whose memory is
# ~/.local/state/nexus/main/flow.sema, which it opens and upgrades from 0.54.7
# in place. It is the version at main, enabled for a user with AgentStack as
# every version is; 0.54.7 is retired. The bare flow and
# flow-meta are its own CLIs.
#
# Its configuration is committed in Flow Memory and changed through the meta
# socket. Home provides its deployment location and executables.
#
# It holds the stable hook: once its unit runs, ~/.local/bin/flow-hook is
# its flow-hook. Memory holds the HarnessHook policy; the next version
# to hold the executable link repoints it.
#
# Being the version at main, it declares the user's Flow CLI configuration,
# ~/.config/nexus/flow-nexus.datom, `{ main }` (vision:nexus-v1):
# `flow '<datom>'` and `flow-meta '<datom>'` read their place from it,
# and no place is typed.
{ config, lib, ... }:
{
  imports = [
    (import ./flow-nexus-place.nix {
      version = "0.55.0";
      slug = "0550";
    })
  ];

  criomosHome.flow0550 = {
    place = "main";
    stableHook = true;
    heapProfile = { };
    # The Nexus at main is held to 3G of memory and no swap, so the kernel
    # stops a runaway Nexus at that size.
    memoryLimit = {
      maximum = "3G";
      swapMaximum = "0";
    };
  };

  systemd.user.services.${config.criomosHome.flow0550.unit}.Unit.X-SwitchMethod = "keep-old";

  home.packages = [ config.criomosHome.flow0550.clients ];

  home.file.".local/bin/flow".source = "${config.criomosHome.flow0550.package}/bin/flow";
  home.file.".local/bin/flow-meta".source = "${config.criomosHome.flow0550.package}/bin/flow-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0550.place == "main") {
    source = "${config.criomosHome.flow0550.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
