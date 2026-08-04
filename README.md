# CriomOS-home

Home profile for CriomOS, as a standalone blueprint flake.

Split out from legacy CriomOS so that:

1. `CriomOS` stays network-neutral and free of desktop-shell inputs
   (niri, noctalia, stylix, emacs sources, vscodium extensions).
2. Home-only deploys can evaluate this flake directly while passing the
   same projected `horizon` and `system` inputs used by CriomOS.

**Status:** active. Tracks [docs/ROADMAP.md](docs/ROADMAP.md).

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

The maintained `lojix-bootstrap` app is re-exported unchanged from this flake
as well as CriomOS. It accepts one explicit inline `BootstrapRun` DOTOS object
and is daemon-free: callers must supply the input mode, builder, test plan,
backend, journal parent, new GC-root path, and terminal-evidence path. Use its
`BuildOnly` variant when activation is not authorized; it has no transport or
activation representation.

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
