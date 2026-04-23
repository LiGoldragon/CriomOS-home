# CriomOS-home

Home profile for CriomOS, as a standalone blueprint flake.

Split out from legacy CriomOS so that:

1. `CriomOS` stays network-neutral and free of desktop-shell inputs
   (niri, noctalia, stylix, emacs sources, vscodium extensions).
2. Non-CriomOS NixOS hosts can consume the same home profile via
   `home-manager switch --flake github:LiGoldragon/CriomOS-home#<user>@<host>`
   once standalone wiring lands.

**Status:** scaffold. Tracks [docs/ROADMAP.md](docs/ROADMAP.md).

## Consumption

From `CriomOS`:
```nix
inputs.criomos-home.url = "github:LiGoldragon/CriomOS-home";
# … CriomOS feeds horizon.user into homeModules.default via _module.args
```

## Layout

Blueprint conventions:

- `modules/home/default.nix` → `homeModules.default`
- `modules/home/<name>.nix` → `homeModules.<name>`
- `lib/default.nix` → `lib`
- `devshell.nix`, `formatter.nix`

## Sibling repos

- [`LiGoldragon/CriomOS`](https://github.com/LiGoldragon/CriomOS) — the OS platform.
- [`LiGoldragon/CriomOS-emacs`](https://github.com/LiGoldragon/CriomOS-emacs) *(planned)* —
  replaces legacy `pkdjz/mkEmacs`. Consumed here, not by CriomOS directly.

## Conventions

- Jujutsu only. Never `git` CLI.
- Mentci three-tuple commit format.
