# Pi Extensions

CriomOS-home installs Pi extensions declaratively. Do not use
`pi install` for persistent extensions: it mutates `$HOME/.pi` and
breaks reproducibility from the flake alone.

## Invariants

- Package every persistent extension as a Nix derivation under
  `packages/<extension>/default.nix`.
- Expose the package through a stable Home Manager path under
  `$HOME/.pi/agent/packages/<extension>`.
- Put only stable, home-relative package sources in Pi settings, for
  example `packages/<extension>`.
- Keep derivation output paths out of `settings.json` and out of Pi's
  prompt context.
- Keep secrets out of Nix outputs and JSON config. Inject them at
  runtime from the environment or `gopass`.
- External extension sources are flake inputs. Their content hashes
  live in `flake.lock`, not as `fetchurl` hashes inside package Nix
  code.

## Why The Stable Symlink Matters

Pi includes paths to its own docs and examples in the default system
prompt. The packaged `pi` binary therefore sets `PI_PACKAGE_DIR` to the
stable Home Manager symlink:

```text
$HOME/.local/share/criomos/pi/package
```

That symlink points at the built Pi package, but Pi sees the stable home
path instead of a derivation output path. Extension package paths follow
the same rule: the live Pi settings file names
`packages/<extension>`, which Pi resolves below `$HOME/.pi/agent`.

## Adding An Extension

1. Add the extension source as a flake input.

   For a simple published npm package, use a non-flake `type = "file"`
   input. Bump the version in the URL, then update the input lock.

   ```nix
   my-extension-src = {
     type = "file";
     url = "https://registry.npmjs.org/<scope>/<tarball>.tgz";
     flake = false;
   };
   ```

2. Create `packages/<extension>/default.nix`.

   Install the package root below
   `$out/share/pi-packages/<extension>`.

   ```nix
   { inputs, pkgs, ... }:
   pkgs.stdenvNoCC.mkDerivation {
     pname = "<extension>";
     version = "<version>";

     dontUnpack = true;
     dontBuild = true;

     installPhase = ''
       runHook preInstall

       packageRoot=$out/share/pi-packages/<extension>
       mkdir -p "$packageRoot"
       tar -xzf ${inputs.my-extension-src} -C "$packageRoot" --strip-components=1

       runHook postInstall
     '';
   }
   ```

   If the extension has a larger npm dependency closure, prefer a normal
   `buildNpmPackage` derivation with a committed lockfile, a flat closure
   of flake-input tarballs, or another fully pinned dependency plan. Do
   not let `npm install` run in the user's home directory.

3. Wire the derivation into `modules/home/profiles/min/pi-models.nix`.

   ```nix
   let
     my-extension = pkgs.callPackage ../../../../packages/my-extension { inherit inputs; };
   in
   {
     home.file.".pi/agent/packages/my-extension".source =
       "${my-extension}/share/pi-packages/my-extension";
   }
   ```

4. Add the stable package source to `piSettingsConfig.packages`.

   ```nix
   piSettingsConfig = {
     packages = [
       "packages/my-extension"
     ];
   };
   ```

   The `/packages` setting is managed with `hexis` mode `always`.
   Treat it as the declarative list of enabled Pi packages.

5. Add runtime secret injection only if the extension needs it.

   Secret-bearing extensions should read environment variables at
   runtime. If the secret lives in `gopass`, inject it in the Pi wrapper
   in `packages/pi/default.nix`, following the `LINKUP_API_KEY` pattern:

   ```nix
   --run 'export SOME_API_KEY="''${SOME_API_KEY:-$(${pkgs.gopass}/bin/gopass show -o service.example/api-key 2>/dev/null || true)}"'
   ```

   Suppress missing-secret stderr when the extension can cleanly disable
   itself. Do not write secret values into Home Manager config, Pi
   settings, package sources, or derivation files.

## Current Example

`pi-criomos` is the daily local package:

- `packages/pi-criomos/default.nix` installs the CriomOS dark/light
  themes and a generic `live-theme-control` extension. The extension
  starts its Unix-stream server during `session_start`, shuts it down
  during `session_shutdown`, accepts `dark\n` and `light\n`, and maps
  those modes to `criomos-dark` and `criomos-light` by default. It does
  not poll, watch sidecar files, or read a Chroma `current-mode` file.
- `operator-safety.ts` is not part of the default package. The basic
  CriomOS Pi profile is YOLO-mode: theme support, Linkup web/search
  support, subagents support, and continuation support, without repeated
  mutation-confirmation gates.

`pi-linkup` is the small reference external package:

- `flake.nix` declares `pi-linkup-src` and `pi-utils-ui-src`.
- `packages/pi-linkup/default.nix` unpacks those lock-file-pinned
  inputs.
- `modules/home/profiles/min/pi-models.nix` exposes it at
  `$HOME/.pi/agent/packages/pi-linkup`.
- Pi settings enable it as `packages/pi-linkup`.
- `packages/pi/default.nix` injects `LINKUP_API_KEY` from
  `gopass show -o linkup.so/api-key` when the variable is not already
  set.

`pi-web-access` remains packaged for rollback and comparison, but it is
not part of the loaded Pi profile:

- `flake.nix` declares `pi-web-access-src` plus a flat flake-input npm
  dependency closure for its runtime imports.
- `packages/pi-web-access/default.nix` unpacks the package and its
  dependencies below the package-local `node_modules` directory.
- `modules/home/profiles/min/pi-models.nix` does not expose it under
  `$HOME/.pi/agent/packages` and does not include `packages/pi-web-access`
  in the managed Pi settings package list.

`pi-continue` is the same-session continuation package:

- `flake.nix` declares `pi-continue-src` as the pinned npm tarball
  source.
- `packages/pi-continue/default.nix` unpacks that source below
  `$out/share/pi-packages/pi-continue`.
- `modules/home/profiles/min/pi-models.nix` exposes it at
  `$HOME/.pi/agent/packages/pi-continue` and enables it as
  `packages/pi-continue`.
- The package provides the `/continue` command and mid-run continuation
  guard so long Pi tool loops can compact and resume from a structured
  same-session handoff.

## Validation

Before committing, run:

```sh
nix fmt -- flake.nix packages/<extension>/default.nix modules/home/profiles/min/pi-models.nix checks/pi-harness-profile/default.nix
nix eval --raw .#packages.x86_64-linux.<extension>.drvPath >/dev/null
nix eval --json .#packages.x86_64-linux --apply 'builtins.attrNames'
jj diff --stat
```

CriomOS process still applies: push before building, and build from
origin with `--refresh` when a full build is needed.
