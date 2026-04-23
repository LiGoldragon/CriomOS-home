# CriomOS-home — Roadmap

## Phase 0 — scaffold

- [x] `flake.nix` — blueprint + desktop inputs
- [x] `devshell.nix`, `formatter.nix`
- [x] `modules/home/default.nix` — empty aggregate
- [x] `lib/default.nix` — placeholder
- [x] `README.md`, `AGENTS.md`

## Phase 1 — base port

- [ ] Port `baseModule.nix` (theme faces, session vars, XDG) from legacy.
- [ ] Port `min/default.nix` → `modules/home/profiles/min.nix`.
- [ ] Port `min/niri.nix`, `min/sfwbar.nix` → `modules/home/{niri,sfwbar}.nix`.
- [ ] Wire `homeModules.default` to import base + min.
- [ ] Verify standalone: `home-manager switch --flake .#<user>@<host>`.

## Phase 2 — med / max

- [ ] Port `med/{default,qutebrowser,element,mentci-cli}.nix`.
- [ ] Port `max/{default,firefox}.nix`.
- [ ] Profile selector: `horizon.user.methods.sizedAtLeast.{min,med,max}`
      drives which profile imports into `homeModules.default`.

## Phase 3 — editor subsystems

- [ ] Port `vscodium/` as `modules/home/vscodium.nix`.
- [ ] Wire `criomos-emacs` input once the split repo lands; consume its
      `homeModules.default` from `modules/home/emacs.nix`.

## Phase 4 — integration

- [ ] `CriomOS` consumes `inputs.criomos-home.homeModules.default` in
      `crioZones.<cluster>.<node>.home.<user>`.
- [ ] `home-manager switch --flake` standalone path documented in README.

## Open questions

- **User species ↔ profile:** does `user.methods.isCodeDev` map to `max` or
  does the ladder stay driven purely by `user.size`? Revisit once
  horizon-rs exposes both fields in one enriched document.
