# CriomOS-home

The minimum Home profile installs the pinned `flow-id` parent-flow helper from
`harness`. Codex parents claim from their normalized UUID's `[23:29]`
characters; Claude parents invoke `flow-id claude --flows-root
ABSOLUTE_DIRECTORY --parent-session UUID` with their canonical lowercase UUIDv4
or UUIDv5 parent session and claim its first six literal hexadecimal characters. Both extend on
collisions. Child threads receive `FLOW_ID` and `FLOW_DIRECTORY` and do not
invoke the helper.

Home profile for CriomOS, as a standalone blueprint flake.

Split out from legacy CriomOS so that:

1. `CriomOS` stays network-neutral and free of desktop-shell inputs
   (niri, noctalia, stylix, emacs sources, vscodium extensions).
2. Home consumes the `horizon` and `system` projections supplied by
   CriomOS; it has no deployment authority.

**Status:** active. Tracks [docs/ROADMAP.md](docs/ROADMAP.md).

## Consumption

From `CriomOS`:
```nix
inputs.criomos-home.url = "github:LiGoldragon/CriomOS-home";
inputs.criomos-home.inputs.horizon.follows = "horizon";
inputs.criomos-home.inputs.system.follows = "system";
inputs.criomos-home.inputs.pkgs.follows = "pkgs";
```

Deployment, bootstrap, and activation authority belong to CriomOS. Lojix is
OS-owned: CriomOS-home neither depends on it nor exports or executes it.
Home only consumes generic `horizon` and `system` projections that CriomOS
supplies to its modules.

## Layout

Blueprint conventions:

- `modules/home/default.nix` → `homeModules.default`
- `modules/home/<name>.nix` → `homeModules.<name>`
- `lib/default.nix` → `lib`
- `devshell.nix`, `formatter.nix`

## Sibling repos

- `LiGoldragon/CriomOS` — the OS platform.
- `LiGoldragon/CriomOS-emacs` *(planned)* —
  replaces legacy `pkdjz/mkEmacs`. Consumed here, not by CriomOS directly.

## Conventions

- Jujutsu only. Never `git` CLI.
- Mentci three-tuple commit format.
