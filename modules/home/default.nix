{ flake, inputs, ... }:

# homeModules.default — top aggregate for the CriomOS home profile.
#
# Consumers (CriomOS userHomes.nix, or standalone
# `home-manager switch --flake`) include this module and pass via
# extraSpecialArgs:
#
#   { horizon, user, inputs, ... }
#
# - horizon: from lojix's projection (the per-(cluster, node) view).
# - user:    horizon.users.<userName>, set per-user in CriomOS userHomes.
# - inputs:  CriomOS-home's own flake inputs (niri-flake, noctalia,
#            stylix, vscodium-ext, etc.) — this aggregate forwards
#            them to inner modules that need them (e.g. niri-flake's
#            home module).

{ config, lib, horizon ? null, user ? null, inputs ? null, ... }:
{
  imports = [
    # The natural list — base + profiles + editors:
    #   ./base.nix
    #   ./profiles/min
    #   ./profiles/med
    #   ./profiles/max
    #   ./neovim/neovim
    #   ./vscodium/vscodium
    #   ./emacs/emacs (blocked on pkdjz.mkEmacs — emacs-plb bead)
    #
    # Currently DISABLED. Wire-up attempt 2026-04-25 surfaced an
    # architecture issue: every home module reads `inputs.<X>` for
    # inputs that are declared in CriomOS-home's own flake (stylix,
    # niri-flake, noctalia, pi-mentci, mentci-tools), but consumers
    # like CriomOS userHomes.nix pass their OWN `inputs` via
    # extraSpecialArgs. CriomOS-home's flake inputs are not visible
    # to its own home modules through that channel.
    #
    # Proper fix: have CriomOS-home's homeModules.default inject its
    # own inputs (and import the upstream homeModules for stylix /
    # noctalia / pi-mentci that those refs depend on). Tracked as a
    # follow-up to home-tcj. See reports/0019 for the full audit.
  ]
  # Compositor home module from niri-flake — pulled in only when the
  # consumer actually has niri-flake in its flake inputs (it's the
  # consumer's choice whether to depend on niri). Skip otherwise.
  ++ lib.optional (inputs != null && inputs ? niri-flake) inputs.niri-flake.homeModules.config;

  config = { };
}
