# Agent Bootstrap — CriomOS-home

Before making changes:

1. Read `docs/ROADMAP.md`.
2. Read the design essay at `../criomos-archive/proposals/CRIOMOS-NEXT.md`.
3. Read `/home/li/.claude/projects/-home-li-git-CriomOS/memory/MEMORY.md`.

## Scope

Home-manager modules for the CriomOS desktop profile. This repo owns:

- Niri compositor config, noctalia-shell IPC, stylix theming.
- Vscodium + extensions, Claude-for-Linux wrapper.
- Qutebrowser, Firefox, Element.
- Emacs — consumed from `criomos-emacs` once split.
- Profile ladder: `min`, `med`, `max`.

It does NOT own:

- NixOS-level concerns (networking, services, users). Those are in `CriomOS`.
- Horizon schema or method computation. Those are in `horizon-rs`.

## Hard rules (inherited)

- Jujutsu only.
- Never live-activate HM generations with compositor / input changes.
- Never SIGHUP niri.
- Push before real builds.
- Never print Nix store paths into agent context.
