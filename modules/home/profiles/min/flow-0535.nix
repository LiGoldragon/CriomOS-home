# Flow Nexus 0.53.5, built per crate on the build base: its configured package
# and its clients under their versioned names (flow-nexus-0.53.5,
# flow-nexus-meta-0.53.5).
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
# `flow-nexus '<datom>'` and `flow-nexus-meta '<datom>'` of 0.53.5 read their
# place from it, and no place is typed. The 0.53.1 clients read no configuration.
{ config, lib, inputs, ... }:
{
  imports = [
    (import ./flow-nexus-place.nix {
      version = "0.53.5";
      slug = "0535";
    })
  ];

  criomosHome.flow0535 = {
    place = "main";
    stableHook = true;
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0533.datom";
    # The living configuration of the machines, kept in the cluster repository.
    declarationSource = "${inputs.goldragon}/metaflows-0533.datom";
    messageNexus = null;
    # 0.53.3 and later read a Model where earlier versions read a layer.
    configurationDirectory = ./flow-nexus-config-0533;
  };

  home.packages = [ config.criomosHome.flow0535.clients ];

  home.file.".local/bin/flow-nexus".source = "${config.criomosHome.flow0535.package}/bin/flow-nexus";
  home.file.".local/bin/flow-nexus-meta".source = "${config.criomosHome.flow0535.package}/bin/flow-nexus-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0535.place == "main") {
    source = "${config.criomosHome.flow0535.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
