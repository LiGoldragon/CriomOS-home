# Flow Nexus 0.60.4, built per crate on the build base: its package and its
# clients under their versioned names (flow-0.60.4, flow-meta-0.60.4). It
# starts in its place (flow-nexus-place.nix): main, the place every flow
# reports to, whose sockets are $XDG_RUNTIME_DIR/nexus/main/ and whose memory
# is ~/.local/state/nexus/main/flow.sema, which it opens and upgrades in
# place. It is the version at main, enabled for a user with AgentStack as
# every version is. The bare flow and flow-meta are its own CLIs.
#
# Every version is its own unit, named for it (flow-nexus-0604). A new
# version at main is a new input, a new module and a new unit, and the Home
# activation stops the previous version's unit and starts this one: nothing is
# stopped by hand before a switch, so the user manager's re-execution during
# the system switch, which starts every inactive unit default.target wants,
# finds the previous version still running and starts nothing on it.
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
      version = "0.60.4";
      slug = "0604";
    })
  ];

  criomosHome.flow0604 = {
    place = "main";
    stableHook = true;
    glibcAllocator = {
      arenaMaximum = 2;
      mmapThreshold = 1048576;
      trimThreshold = 131072;
    };
    # The Nexus at main is held to 3G of memory and no swap, so the kernel
    # stops a runaway Nexus at that size.
    memoryLimit = {
      maximum = "3G";
      swapMaximum = "0";
    };
  };

  systemd.user.services.${config.criomosHome.flow0604.unit}.Unit.X-SwitchMethod = "keep-old";

  home.packages = [ config.criomosHome.flow0604.clients ];

  home.file.".local/bin/flow".source = "${config.criomosHome.flow0604.package}/bin/flow";
  home.file.".local/bin/flow-meta".source = "${config.criomosHome.flow0604.package}/bin/flow-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0604.place == "main") {
    source = "${config.criomosHome.flow0604.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
