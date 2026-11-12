# Flow Nexus 0.54.7, built per crate on the build base: its configured package
# and its clients under their versioned names (flow-nexus-0.54.7,
# flow-nexus-meta-0.54.7). A patch release keeps the 0.54 slug, 0540, so its
# input, units and option are those of 0.54.0, and the switch restarts
# flow-nexus-0540 on the same memory.
# It starts in its place (flow-nexus-place.nix): main, the place every flow
# reports to, whose sockets are $XDG_RUNTIME_DIR/nexus/main/ and whose memory
# is ~/.local/state/nexus/main/flow.sema. It is the version at main, enabled
# for a user with AgentStack as every version is; 0.53.1 is retired
# (flows/ff3882/cutover-0533.md). The bare flow-nexus and flow-nexus-meta are
# its own CLIs.
#
# It holds the stable hook: once its unit runs, ~/.local/bin/flow-nexus-hook is
# its flow-nexus-hook and its declared HarnessHook, so every Claude flow it launches
# runs that path, which the next version to hold it repoints.
#
# Being the version at main, it declares the user's Flow CLI configuration,
# ~/.config/nexus/flow-nexus.datom, `{ main }` (vision:nexus-v1):
# `flow-nexus '<datom>'` and `flow-nexus-meta '<datom>'` of 0.54.7 read their
# place from it, and no place is typed. The 0.53.1 clients read no configuration.
{ config, lib, inputs, ... }:
{
  imports = [
    (import ./flow-nexus-place.nix {
      version = "0.54.7";
      slug = "0540";
    })
  ];

  criomosHome.flow0540 = {
    place = "main";
    stableHook = true;
    # The complex definition, kept in its own repository.
    ownerDeclarations = {
      models = "${inputs.complex}/models-0533.datom";
      thresholds = "${inputs.complex}/thresholds-0533.datom";
      metaflows = "${inputs.complex}/metaflows-0533.datom";
    };
    messageNexus = null;
    # Every launch opens its pane in Herdr's default session, where the
    # flows run (Flow 0.54.3's Configure.Nexus names it).
    herdrSession = "default";
    # 0.53.3 and later read a Model where earlier versions read a layer.
    configurationDirectory = ./flow-nexus-config-0533;
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
  systemd.user.services.${config.criomosHome.flow0540.unit}.Service = {
    MemoryMax = "3G";
    MemorySwapMax = "0";
  };

  home.packages = [ config.criomosHome.flow0540.clients ];

  home.file.".local/bin/flow-nexus".source = "${config.criomosHome.flow0540.package}/bin/flow-nexus";
  home.file.".local/bin/flow-nexus-meta".source = "${config.criomosHome.flow0540.package}/bin/flow-nexus-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0540.place == "main") {
    source = "${config.criomosHome.flow0540.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
