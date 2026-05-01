# Agent instructions — CriomOS-home

You **MUST** read AGENTS.md at `github:ligoldragon/lore` — the workspace contract.

You **MUST** read CriomOS's AGENTS.md (sibling repo) — CriomOS-cluster rules apply here.

## Repo role

Home-manager modules for the CriomOS desktop profile. Owns:

- Niri compositor config, noctalia-shell IPC, stylix theming.
- Vscodium + extensions, Claude-for-Linux wrapper.
- Qutebrowser, Firefox, Element.
- Emacs (consumed from `CriomOS-emacs`).
- Profile ladder: `min`, `med`, `max`.

NixOS-level concerns (networking, services, users) live in `CriomOS`; horizon schema and method computation live in `horizon-rs`.

First thing: run `bd list --status open`. Read `docs/ROADMAP.md`.

## Carve-outs

- Live-activating HM generations with compositor / input changes risks losing the session. Apply through a safe path (rebuild + new login).
