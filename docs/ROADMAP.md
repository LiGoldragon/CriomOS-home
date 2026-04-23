# CriomOS-home — Roadmap

Active work is tracked in beads — `bd list --status open`. The list
below is a high-level porting order; per-task detail lives in the
beads issue it points to.

## Phase 0 — scaffold (done)

- [x] `flake.nix` — blueprint + desktop inputs
- [x] `devshell.nix`, `formatter.nix`
- [x] `modules/home/default.nix` aggregate (placeholder; see `home-tcj`)
- [x] `lib/default.nix` — placeholder
- [x] `README.md`, `AGENTS.md`
- [x] `modules/home/{base.nix, profiles/{min,med,max}/, emacs/, vscodium/, neovim/, nonNix/}` — verbatim copies from `criomos-archive`.

## Phase 1 — adapt to new horizon shape

- [ ] `home-f68` — modules in `modules/home/` are verbatim copies and
      still consume the legacy `horizon.node.methods.X` shape and
      `users.<u>.preCriomes.<n>` keys. horizon-rs emits a flat shape
      with `pubKeys`. Per-module rewrite needed; spec at
      [/home/li/git/horizon-rs/docs/DESIGN.md](/home/li/git/horizon-rs/docs/DESIGN.md).
- [ ] `home-tcj` — implement `modules/home/default.nix` aggregate so
      profile / module selection is driven by `horizon.user.sizedAtLeast.*`
      and `horizon.node.behavesAs.*` (flat — no `.methods.` nesting).

## Phase 2 — editor subsystem

- [ ] `home-tl6` — wire `criomos-emacs` as a flake input and re-export
      its `homeModules.default` from `modules/home/emacs.nix`. Blocked
      on the CriomOS-emacs `emacs-plb` conversion landing.

## Phase 3 — CriomOS integration

- [ ] CriomOS consumes `inputs.criomos-home.homeModules.default` in
      `crioZones.<cluster>.<node>.home.<user>`. Tracked in CriomOS as
      part of `CriomOS-cal` (crioZones implementation).
- [ ] Standalone `home-manager switch --flake` path documented in
      `README.md` once the aggregate works.

## Open questions

- **User species ↔ profile:** does `horizon.user.isCodeDev` map to `max`,
  or does the ladder stay driven purely by `horizon.user.sizedAtLeast`?
  Revisit while implementing `home-tcj`.
