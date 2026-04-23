{ flake, inputs, ... }:

# homeModules.default — top aggregate for the CriomOS home profile.
#
# Consumers (CriomOS crioZones.*.home.<user>, or standalone
# `home-manager switch --flake`) include this module and pass:
#
#   _module.args = {
#     horizon  = <from CriomOS lib.mkHorizon>;
#     user     = <horizon.users.<userName>>;
#     pkdjz    = <legacy; to be removed>;
#     world    = <legacy; to be removed>;
#   };
#
# Empty on purpose in Phase 0. Split modules land here as they port over:
#   ./base.nix
#   ./emacs.nix          (or inputs.criomos-emacs.homeModules.default)
#   ./vscodium.nix
#   ./niri.nix  ./sfwbar.nix  ./qutebrowser.nix  ./element.nix  ./firefox.nix
#   ./profiles/min.nix  ./profiles/med.nix  ./profiles/max.nix

{ config, lib, horizon ? null, user ? null, ... }:
{
  imports = [ ];

  config = { };
}
