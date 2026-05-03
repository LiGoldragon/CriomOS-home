# CriomOS-home

Home profile for CriomOS, as a standalone blueprint flake.

Split out from legacy CriomOS so that:

1. `CriomOS` stays network-neutral and free of desktop-shell inputs
   (niri, noctalia, stylix, emacs sources, vscodium extensions).
2. Home-only deploys can evaluate this flake directly while passing the
   same projected `horizon` and `system` inputs used by CriomOS.

**Status:** scaffold. Tracks [docs/ROADMAP.md](docs/ROADMAP.md).

## Consumption

From `CriomOS`:
```nix
inputs.criomos-home.url = "github:LiGoldragon/CriomOS-home";
inputs.criomos-home.inputs.horizon.follows = "horizon";
inputs.criomos-home.inputs.system.follows = "system";
inputs.criomos-home.inputs.pkgs.follows = "pkgs";
```

Direct home-only deploys build:

```text
homeConfigurations.<user>.activationPackage
```

with `horizon` and `system` overridden by lojix.

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
