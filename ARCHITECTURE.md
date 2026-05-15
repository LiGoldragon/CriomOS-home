# ARCHITECTURE — CriomOS-home

home-manager profile as a standalone flake and CriomOS module.
Imported by `github:LiGoldragon/CriomOS` for full system deploys and
evaluated directly for home-only deploys.

## Role

Per-user configuration for the operator. Provides shell, dot-
files, package selections, and integration with
`github:LiGoldragon/CriomOS-emacs`.

Detailed staging lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).
Pi extension packaging lives in
[`docs/pi-extensions.md`](docs/pi-extensions.md).

## Boundaries

Owns:

- `modules/` — home-manager modules.
- `packages/` — user-scoped packages and configurations.
- `homeConfigurations` — direct Home Manager activation packages keyed
  by projected horizon users.
- The user-facing Rust toolchain installed into profiles. Its canonical
  package is `packages.rust-toolchain`, pinned by this flake's lockfile.

Does not own:

- System-level configuration — that's CriomOS.
- Emacs internals — that's CriomOS-emacs.
- Rust toolchains for building individual Rust application repos when
  they intentionally pin their own compiler through their own flakes.

Cluster-specific choices enter through projected Horizon data. Home
modules must not branch on concrete node names from a particular cluster;
they consume semantic roles and capabilities and may render node names
only as identities, URLs, labels, or diagnostics.

## Status

CANON. Active.

## Cross-cutting context

- Project-wide architecture: criome's `ARCHITECTURE.md`.
