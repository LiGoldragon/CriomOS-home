{ flake, inputs, ... }:

# homeModules.default — top aggregate for the CriomOS home profile.
#
# Consumers (CriomOS userHomes.nix, or standalone
# `home-manager switch --flake`) include this module and pass via
# extraSpecialArgs:
#
#   { horizon, user, inputs, ... }
#
# - horizon: from the OS-supplied projection (the per-(cluster, node) view).
# - user:    horizon.users.<userName>, set per-user in CriomOS userHomes.
# - inputs:  CriomOS-home's own flake inputs (niri-flake, noctalia,
#            stylix, vscodium-ext, etc.) — this aggregate forwards
#            them to inner modules that need them (e.g. niri-flake's
#            home module).

{
  config,
  lib,
  horizon ? null,
  user ? null,
  inputs ? null,
  ...
}:
{
  # Note: stylix.homeModules.stylix + niri-flake.homeModules.config +
  # noctalia.homeModules.default are imported by the wrapper in
  # CriomOS-home/flake.nix's `homeModules.default`. `inputs` here is
  # CriomOS-home's own flake inputs (the wrapper overrides
  # _module.args.inputs).
  imports = [
    ./core-packages.nix
    ./text-scale.nix
    ./visual-theme.nix
    ./desktop-database.nix
    ./base.nix
    ./profiles/min
    ./profiles/min/pi-models.nix
    # Agent Intercom adapters are user-local. They do not depend on a node
    # service; generic Edge plus medium profile capability selects optional
    # desktop-app support, with no node identity, remote transport, or
    # credential control.
    ./profiles/min/agent-intercom.nix
    ./profiles/min/claude-remote-control.nix
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
    ./profiles/min/ui-priority.nix
    ./profiles/min/dictation.nix
    ./profiles/min/spirit.nix
    # Aggregator — supervises the local transcript/evidence recovery daemon
    # and installs wrappers with the same user-scoped configuration path.
    ./profiles/min/aggregator.nix
    # Orchestrate — supervises the multi-agent claim/coordination daemon
    # (systemd --user unit + pinned flake input).
    ./profiles/min/orchestrate.nix
    # Message — supervises the messenger daemon (durable agent-identity
    # map + delivery registry in messenger.sema; systemd --user unit +
    # pinned flake input).
    ./profiles/min/message.nix
    # Chroma — visual-state daemon (theme + warmth + brightness).
    # Replaces darkman + nightshift + the brightness shell wrapper.
    # Per-user systemd unit + apply script + default config.nota.
    ./profiles/min/chroma.nix
    # Despite the filename, this configures programs.noctalia
    # (bar widgets, idle timer, lock timeout). Without it the user
    # gets noctalia's upstream defaults.
    ./profiles/min/sfwbar.nix
    ./profiles/min/active-network.nix
    ./profiles/min/bitwarden.nix
    ./profiles/med
    ./profiles/med/cli-tools.nix
    ./profiles/med/codium.nix
    ./profiles/med/emacs.nix
    # NOT importing ./profiles/med/element.nix here — that file declares
    # `systemd.services.nginx-element` (system-level, not user). It belongs
    # in a CriomOS NixOS module, not in this home-manager aggregate.
    # Archive carried it as an orphan file too; left alone for now.
    ./profiles/med/qutebrowser.nix
    ./profiles/max
    # browser-use, wired to the local Gemma 4 vision model. Large-tier,
    # alongside Chrome — a sibling module, not imported by ./profiles/max.
    ./profiles/max/browser-use.nix
    ./neovim/neovim
    ./vscodium/vscodium
  ];

  config = { };
}
