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

1. Create `packages/<extension>/default.nix`.

   For a simple published npm package, fetch the package tarball and any
   small runtime dependencies explicitly. Install the package root below
   `$out/share/pi-packages/<extension>`.

   ```nix
   { pkgs, ... }:
   let
     extension = pkgs.fetchurl {
       url = "https://registry.npmjs.org/<scope>/<tarball>.tgz";
       hash = "<fixed-output-hash>";
     };
   in
   pkgs.stdenvNoCC.mkDerivation {
     pname = "<extension>";
     version = "<version>";

     dontUnpack = true;
     dontBuild = true;

     installPhase = ''
       runHook preInstall

       packageRoot=$out/share/pi-packages/<extension>
       mkdir -p "$packageRoot"
       tar -xzf ${extension} -C "$packageRoot" --strip-components=1

       runHook postInstall
     '';
   }
   ```

   If the extension has a larger npm dependency closure, prefer a normal
   `buildNpmPackage` derivation with a committed lockfile or another
   fully pinned dependency plan. Do not let `npm install` run in the
   user's home directory.

2. Wire the derivation into `modules/home/profiles/min/pi-models.nix`.

   ```nix
   let
     my-extension = pkgs.callPackage ../../../../packages/my-extension { };
   in
   {
     home.file.".pi/agent/packages/my-extension".source =
       "${my-extension}/share/pi-packages/my-extension";
   }
   ```

3. Add the stable package source to `piSettingsConfig.packages`.

   ```nix
   piSettingsConfig = {
     packages = [
       "packages/my-extension"
     ];
   };
   ```

   The `/packages` setting is managed with `hexis` mode `always`.
   Treat it as the declarative list of enabled Pi packages.

4. Add runtime secret injection only if the extension needs it.

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

`pi-linkup` is the reference implementation:

- `packages/pi-linkup/default.nix` fetches the `@aliou/pi-linkup`
  tarball and its runtime UI helper.
- `modules/home/profiles/min/pi-models.nix` exposes it at
  `$HOME/.pi/agent/packages/pi-linkup`.
- Pi settings enable it as `packages/pi-linkup`.
- `packages/pi/default.nix` injects `LINKUP_API_KEY` from
  `gopass show -o linkup.so/api-key` when the variable is not already
  set.

## Validation

Before committing, run:

```sh
nix fmt -- packages/pi/default.nix packages/<extension>/default.nix modules/home/profiles/min/pi-models.nix
nix eval --raw .#packages.x86_64-linux.<extension>.drvPath >/dev/null
nix eval --json .#packages.x86_64-linux --apply 'builtins.attrNames'
git diff --check
```

CriomOS process still applies: push before building, and build from
origin with `--refresh` when a full build is needed.
