# ARCHITECTURE — CriomOS-home

home-manager profile as a standalone flake and CriomOS module.
Imported by [CriomOS](https://github.com/LiGoldragon/CriomOS) for full
system deploys and evaluated directly for home-only deploys.

## Role

Per-user configuration for the operator. Provides shell, dot-
files, package selections, and integration with
[CriomOS-emacs](https://github.com/LiGoldragon/CriomOS-emacs).

Detailed staging lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).
Pi extension packaging lives in
[`docs/pi-extensions.md`](docs/pi-extensions.md).

## Boundaries

Owns:

- `modules/` — home-manager modules.
- `packages/` — user-scoped packages and configurations.
- `homeConfigurations` — direct Home Manager activation packages keyed
  by projected horizon users.

Does not own:

- System-level configuration — that's CriomOS.
- Emacs internals — that's CriomOS-emacs.

Cluster-specific choices enter through projected Horizon data. Home
modules must not branch on concrete node names from a particular cluster;
they consume semantic roles and capabilities and may render node names
only as identities, URLs, labels, or diagnostics.

## Status

CANON. Active.

## Cross-cutting context

- Project-wide architecture: criome's `ARCHITECTURE.md`.
