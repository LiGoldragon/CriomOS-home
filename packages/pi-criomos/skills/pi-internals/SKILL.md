---
name: pi-internals
description: Pi harness internals for CriomOS/Nix work. Load explicitly when changing Pi itself, its package, patches, prompts, skills, extensions, themes, or harness behavior.
disable-model-invocation: true
---

# Pi Internals on CriomOS

## Use this skill when

Use this skill for Pi harness internals work: Pi source behavior, package
patches, prompts, skills, extensions, themes, settings schema, or the Nix
packaging that delivers them.

This skill is hidden from the default skill list. Load it explicitly with
`/skill:pi-internals` or an explicit skill path when internals guidance is
needed.

## Source and deployment model

CriomOS deploys Pi through CriomOS-home. Persistent Pi changes are Nix
source changes, not live edits under `$HOME/.pi` and not edits under
`/nix/store`.

- Pi upstream source is the `pi-src` flake input in CriomOS-home.
- The package derivation is `packages/pi/default.nix`.
- Local CriomOS Pi package content lives under `packages/pi-criomos/`.
- Home Manager wiring for normal and testing Pi profiles lives in
  `modules/home/profiles/min/pi-models.nix`.
- Package, prompt, skill, extension, theme, and settings changes deploy
  through Home Manager activation or through a CriomOS Lojix deployment.

## How to inspect Pi internals

Inspect source, README files, docs, and examples when the task depends on Pi
behavior. Use Nix to materialize or reference the pinned source. Keep raw store
paths out of reports, commits, prompts, and chat summaries.

Helpful read targets in the pinned source include:

- `packages/coding-agent/src/core/system-prompt.ts`
- `packages/coding-agent/src/core/resource-loader.ts`
- `packages/coding-agent/src/core/skills.ts`
- `docs/skills.md`, `docs/packages.md`, `docs/extensions.md`, and related
  cross-references when changing those surfaces

Treat installed source copies and derivation outputs as read-only evidence.
Never patch files in `/nix/store`; make the change in CriomOS-home source and
let Nix rebuild the output.

## Implementation rules

- Prefer declarative Home Manager files, package derivation content, or patches
  committed under `packages/pi/patches/`.
- Keep package inputs portable: upstream archives and repositories are flake
  inputs, with content hashes in `flake.lock`.
- Keep stable home-relative package references in Pi settings, such as
  `packages/pi-criomos`; do not write derivation output paths into Pi settings.
- Use Pi's `SYSTEM.md` and `APPEND_SYSTEM.md` replacement hooks through
  Home Manager files when changing persistent prompt behavior.
- Use `disable-model-invocation: true` for skills that should be loadable by
  command but hidden from the default prompt.
- Respect the active role and action-space restrictions. Do not use a Pi
  internals workaround to bypass orchestration, hard-mode, Spirit, or
  repository closeout rules supplied by the active task.
- Avoid stateful mutation as the solution. A temporary local file can be an
  inner-loop probe, but the committed fix belongs in Nix-managed source.

## Validation

Run the narrow Nix check or build that proves the touched surface. Common
checks for this package surface are:

```sh
nix eval --raw .#packages.x86_64-linux.pi-criomos.drvPath >/dev/null
nix build .#checks.x86_64-linux.pi-harness-profile --no-link --print-build-logs
nix build .#checks.x86_64-linux.pi-criomos-package-load --no-link --print-build-logs
```

For deployable changes, push the commit before treating a build from origin or
a CriomOS deployment as final evidence.
