# Flow Nexus 0.53.1 at its own place: store
# ~/.local/state/flow-0531, sockets $XDG_RUNTIME_DIR/flow-0531, its own
# mutable declaration file and configuration directory. It protects the
# Psyche core Fable address. Retired at the 0.53.3 cutover: no unit, no bare
# name; its memory stays at ~/.local/state/flow-0531 for rollback.
{ config, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.53.1";
      slug = "0531";
    })
  ];

  criomosHome.flow0531 = {
    enable = false;
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0531.datom";
    configurationDirectory = ./flow-nexus-config-0531;
    trailingConfigurationFiles = [
      "harness-flags.datom"
      "investigation.datom"
      "default-minutes.datom"
      "protected-addresses.datom"
    ];
    messageNexus = null;
  };
}
