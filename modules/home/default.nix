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
    # Compositor home module from niri-flake — pulled in only when the
    # consumer actually has niri-flake in its flake inputs (it's the
    # consumer's choice whether to depend on niri). Skip otherwise.
  ] ++ lib.optional (inputs != null && inputs ? niri-flake) inputs.niri-flake.homeModules.config;

  config = { };
}
