# ARCHITECTURE — CriomOS-home

home-manager profile as a CriomOS module. nix-flake-shaped;
imported by [CriomOS](https://github.com/LiGoldragon/CriomOS).

## Role

Per-user configuration for the operator. Provides shell, dot-
files, package selections, and integration with
[CriomOS-emacs](https://github.com/LiGoldragon/CriomOS-emacs).

Detailed staging lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Boundaries

Owns:

- `modules/` — home-manager modules.
- `packages/` — user-scoped packages and configurations.

Does not own:

- System-level configuration — that's CriomOS.
- Emacs internals — that's CriomOS-emacs.

## Status

CANON. Active.

## Cross-cutting context

- Project-wide architecture:
  [criome/ARCHITECTURE.md](https://github.com/LiGoldragon/criome/blob/main/ARCHITECTURE.md)
