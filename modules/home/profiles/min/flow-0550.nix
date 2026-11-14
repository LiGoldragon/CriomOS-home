# Flow Nexus 0.55.0, built per crate on the build base: its configured package
# and its clients under their versioned names (flow-nexus-0.55.0,
# flow-nexus-meta-0.55.0). It starts in its place (flow-nexus-place.nix):
# main, the place every flow reports to, whose sockets are
# $XDG_RUNTIME_DIR/nexus/main/ and whose memory is
# ~/.local/state/nexus/main/flow.sema, which it opens and upgrades from 0.54.7
# in place. It is the version at main, enabled for a user with AgentStack as
# every version is; 0.54.7 is retired. The bare flow-nexus and
# flow-nexus-meta are its own CLIs.
#
# Every family it is configured with is declared in flow-nexus-config, in
# meta-signal-flow 78's shape: the models, the thresholds and the permaflows,
# each permaflow carrying its own leave-outs, among them.
#
# It holds the stable hook: once its unit runs, ~/.local/bin/flow-nexus-hook is
# its flow-nexus-hook and its declared HarnessHook, so every Claude flow it launches
# runs that path, which the next version to hold it repoints.
#
# Being the version at main, it declares the user's Flow CLI configuration,
# ~/.config/nexus/flow-nexus.datom, `{ main }` (vision:nexus-v1):
# `flow-nexus '<datom>'` and `flow-nexus-meta '<datom>'` read their place from it,
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
    messageNexus = null;
    # Every launch opens its pane in Herdr's default session, where the
    # flows run (Flow 0.54.3's Configure.Nexus names it).
    herdrSession = "default";
    # Every family it is configured with, in meta-signal-flow 78's shape.
    configurationDirectory = ./flow-nexus-config;
    # The handover warning: each model warned at 15 percent before its
    # threshold, every 10 minutes, to write its handover and refresh.
    trailingConfigurationFiles = [
      "harness-flags.datom"
      "investigation.datom"
      "default-minutes.datom"
      "handover-policies.datom"
    ];
  };

  # The Nexus at main is held to 3G of memory and no swap, so the kernel
  # stops a runaway Nexus at that size.
  systemd.user.services.${config.criomosHome.flow0550.unit}.Service = {
    MemoryMax = "3G";
    MemorySwapMax = "0";
  };

  home.packages = [ config.criomosHome.flow0550.clients ];

  home.file.".local/bin/flow-nexus".source = "${config.criomosHome.flow0550.package}/bin/flow-nexus";
  home.file.".local/bin/flow-nexus-meta".source = "${config.criomosHome.flow0550.package}/bin/flow-nexus-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0550.place == "main") {
    source = "${config.criomosHome.flow0550.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
