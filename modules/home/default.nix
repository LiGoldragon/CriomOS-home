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
  # Note: stylix.homeModules.stylix + niri-flake.homeModules.config +
  # noctalia.homeModules.default are imported by the wrapper in
  # CriomOS-home/flake.nix's `homeModules.default`. `inputs` here is
  # CriomOS-home's own flake inputs (the wrapper overrides
  # _module.args.inputs).
  imports = [
    ./base.nix
    ./profiles/min
    ./profiles/med
    ./profiles/max
    ./neovim/neovim
    ./vscodium/vscodium
  ];

  config = { };
}
