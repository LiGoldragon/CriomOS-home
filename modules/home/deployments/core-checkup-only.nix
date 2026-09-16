{ ... }:

# Interim deployment shape for the live Message 0.11.1 store.  The OS owns
# the roster projection and the full Home generation; this module only turns
# on core-checkup and publishes the current harness target snapshot.  The
# cluster relay is intentionally absent while Message 0.12 migration is held.
{
  imports = [
    ../core-packages.nix
    ../profiles/min/core-checkup.nix
    ../profiles/min/core-checkup-primary-successor.nix
    ../profiles/min/codex-layer-resume.nix
  ];

  config.criomosHome.coreCheckup.enable = true;
  config.criomosHome.codexLayerResume.enable = true;
}
