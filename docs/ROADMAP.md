# CriomOS-home — Roadmap

Active work is tracked in beads — `bd list --status open`. The list
below is a high-level porting order; per-task detail lives in the
beads issue it points to.

## Phase 0 — repository split (done)

- [x] `flake.nix` — blueprint + desktop inputs
- [x] `devshell.nix`, `formatter.nix`
- [x] `modules/home/default.nix` aggregate (placeholder; see `home-tcj`)
- [x] `lib/default.nix` — placeholder
- [x] `README.md`, `AGENTS.md`
- [x] `modules/home/{base.nix, profiles/{min,med,max}/, emacs/, vscodium/, neovim/, nonNix/}` — home-owned modules.

## Phase 1 — adapt to new horizon shape

- [x] Home modules consume the flat projected horizon shape.
- [x] `modules/home/default.nix` aggregates profile and module
      selection from projected user and node facts.

## Phase 1.5 — architecture guardrails

- [ ] Add focused checks for stateful home paths, generated workspaces,
      and theme configuration so regressions are caught before profile
      activation.
- [ ] Keep cluster-specific values out of CriomOS-home; user, node, and
      cluster truth enters only through the projected horizon.

## Phase 2 — editor subsystem

- [ ] `home-tl6` — wire `criomos-emacs` as a flake input and re-export
      its `homeModules.default` from `modules/home/emacs.nix`. Blocked
      on the CriomOS-emacs `emacs-plb` conversion landing.

## Phase 3 — CriomOS integration

- [x] CriomOS consumes `inputs.criomos-home.homeModules.default`
      through the NixOS home-manager integration.
- [x] Keep deployment and activation authority in CriomOS. Home consumes only
      the generic projections supplied by the OS.

## Open questions

- **User species ↔ profile:** does `horizon.user.isCodeDev` map to `max`,
  or does the ladder stay driven purely by `horizon.user.sizedAtLeast`?
  Revisit while implementing `home-tcj`.
