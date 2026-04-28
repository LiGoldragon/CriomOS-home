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
    # Sibling .nix files in profiles/min/ are individual HM modules, not
    # imported transitively by the directory import (Nix only auto-loads
    # default.nix). Archive's homeModule/default.nix listed each one
    # explicitly; the new-criomos rewrite missed the carry-over, so
    # niri.nix + sfwbar.nix sat as orphans on disk and were silently
    # skipped — the niri keybinds, criomos-lock-{session,listener}
    # services, and the noctalia bar widget config never made it into
    # the home-manager generation. Re-introducing them as explicit
    # imports.
    ./profiles/min/niri.nix
    # Despite the filename, this configures programs.noctalia-shell
    # (bar widgets, idle timer, lock timeout). Without it the user
    # gets noctalia's upstream defaults.
    ./profiles/min/sfwbar.nix
    ./profiles/med
    ./profiles/med/cli-tools.nix
    ./profiles/med/element.nix
    ./profiles/med/qutebrowser.nix
    ./profiles/max
    ./neovim/neovim
    ./vscodium/vscodium
  ];

  config = { };
}
