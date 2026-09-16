{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.criomosHome.codexLayerResume;
  displayName = {
    primary = "Primary";
    secondary = "Secondary";
  };
  recordedCwds = {
    # Recorded in the session_meta event for each reviewed thread. Codex's
    # supported `resume --cd` flag makes this choice explicit and avoids the
    # interactive working-directory picker.
    primary = "/home/li/wt/primary-5f4fea";
    secondary = "/home/li/secondary";
  };
  sourceRoot = "${inputs.codex-layer-resume-source}/tools/codex-layer-resume";
  launcher = pkgs.writeText "codex-layer-resume-launch.mjs" ''
    import { readFileSync } from "node:fs";
    import { spawnSync } from "node:child_process";
    import { homedir } from "node:os";
    import { parseArgs, resolveThread, ResolutionError } from "./codex-layer-resume.mjs";

    const recordedCwds = ${builtins.toJSON recordedCwds};

    const run = (argv) => {
      const { layer, registryPath } = parseArgs(argv, process.env, homedir());
      const cwd = recordedCwds[layer];
      if (typeof cwd !== "string") throw new ResolutionError("no recorded cwd for " + layer);
      let registry;
      try {
        registry = JSON.parse(readFileSync(registryPath, "utf8"));
      } catch (error) {
        throw new ResolutionError("cannot read registry " + registryPath + ": " + error.message);
      }
      const threadId = resolveThread(registry, layer);
      const result = spawnSync("codex", ["resume", "--cd", cwd, threadId], { stdio: "inherit" });
      if (result.error) throw new ResolutionError("could not run codex resume: " + result.error.message);
      return { status: result.status, signal: result.signal };
    };

    try {
      const result = run(process.argv.slice(2));
      if (result.signal) process.kill(process.pid, result.signal);
      else process.exitCode = result.status ?? 1;
    } catch (error) {
      process.stderr.write("codex-layer-resume: " + error.message + "\n");
      process.exitCode = 2;
    }
  '';
  readme = pkgs.writeText "codex-layer-resume-home-readme.md" ''
    # CriomOS Home Codex layer resume

    This Home package wraps the reviewed lane-index snapshot and selects the
    recorded session directory with Codex's supported `resume --cd` option.
    The primary record uses `${recordedCwds.primary}` and the secondary record
    uses `${recordedCwds.secondary}`. The wrapper refuses title-only and stale
    records through the upstream resolver.
  '';
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex-layer-resume";
    version = "0b4f393";
    src = sourceRoot;
    dontBuild = true;
    installPhase = ''
            runHook preInstall
            mkdir -p "$out/bin"
            install -Dm644 codex-layer-resume.mjs "$out/share/codex-layer-resume/codex-layer-resume.mjs"
            install -Dm644 codex-lane-index.json "$out/share/codex-layer-resume/codex-lane-index.json"
            install -Dm644 ${readme} "$out/share/codex-layer-resume/README.md"
            install -Dm644 codex-layer-resume.test.mjs "$out/share/codex-layer-resume/codex-layer-resume.test.mjs"
            install -Dm644 test/codex-lane-index.test.mjs "$out/share/codex-layer-resume/test/codex-lane-index.test.mjs"
            install -Dm644 ${launcher} "$out/share/codex-layer-resume/codex-layer-resume-launch.mjs"

            for layer in primary secondary; do
              cat > "$out/bin/codex-$layer" <<EOF_WRAPPER
      #!/bin/sh
      set -eu
      exec ${pkgs.nodejs}/bin/node "$out/share/codex-layer-resume/codex-layer-resume-launch.mjs" --layer $layer "\$@"
      EOF_WRAPPER
              chmod 0755 "$out/bin/codex-$layer"
            done
            runHook postInstall
    '';
    meta = {
      description = "Guarded primary and secondary Codex lane resume wrappers";
      mainProgram = "codex-primary";
      platforms = lib.platforms.unix;
    };
  };

  colors = config.lib.stylix.colors.withHashtag;
  terminalTheme = pkgs.writeText "codex-layer-resume-ghostty.conf" ''
    # Reuse the active CriomOS base16 palette explicitly for a legible fresh
    # terminal. Chroma owns the normal terminal state; this launcher supplies
    # the same palette so its entry is deterministic at launch time.
    font-family = IosevkaTerm Nerd Font
    font-size = 13
    window-decoration = false
    gtk-titlebar = false
    window-theme = ghostty
    background = ${colors.base00}
    foreground = ${colors.base05}
    cursor-color = ${colors.base05}
    selection-background = ${colors.base02}
    selection-foreground = ${colors.base05}
    palette = 0=${colors.base00}
    palette = 1=${colors.base08}
    palette = 2=${colors.base0B}
    palette = 3=${colors.base0A}
    palette = 4=${colors.base0D}
    palette = 5=${colors.base0E}
    palette = 6=${colors.base0C}
    palette = 7=${colors.base05}
    palette = 8=${colors.base03}
    palette = 9=${colors.base08}
    palette = 10=${colors.base0B}
    palette = 11=${colors.base0A}
    palette = 12=${colors.base0D}
    palette = 13=${colors.base0E}
    palette = 14=${colors.base0C}
    palette = 15=${colors.base07}
  '';

  mkTerminalLauncher =
    layer:
    pkgs.writeShellApplication {
      name = "codex-${layer}-terminal";
      runtimeInputs = [ pkgs.ghostty ];
      text = ''
        exec ${pkgs.ghostty}/bin/ghostty \
          --gtk-single-instance=false \
          --class=net.criome.codex-layer \
          --title="Codex ${displayName.${layer}} — reviewed resume" \
          --config-file=${terminalTheme} \
          --working-directory="$HOME" \
          -e ${package}/bin/codex-${layer} "$@"
      '';
    };

  primaryTerminal = mkTerminalLauncher "primary";
  secondaryTerminal = mkTerminalLauncher "secondary";

  mkDesktopEntry =
    {
      layer,
      launcher,
      comment,
    }:
    pkgs.writeText "codex-${layer}-reviewed-resume.desktop" ''
      [Desktop Entry]
      Type=Application
      Name=Codex ${displayName.${layer}} — reviewed resume
      Comment=${comment}
      Exec=${launcher}/bin/codex-${layer}-terminal
      Terminal=false
      Categories=Development;Utility;
      StartupNotify=true
    '';

  primaryDesktop = mkDesktopEntry {
    layer = "primary";
    launcher = primaryTerminal;
    comment = "Resume the current reviewed primary Codex lane";
  };
  secondaryDesktop = mkDesktopEntry {
    layer = "secondary";
    launcher = secondaryTerminal;
    comment = "Resume the current reviewed secondary Codex lane";
  };

  indexFile = "${package}/share/codex-layer-resume/codex-lane-index.json";
in
{
  options.criomosHome.codexLayerResume = {
    enable = mkEnableOption "the reviewed primary and secondary Codex lane resume wrappers";
  };

  config = mkIf cfg.enable {
    home.packages = [
      package
      primaryTerminal
      secondaryTerminal
    ];

    # The wrapper's default path resolves to this immutable package source.
    # CODEX_LAYER_INDEX and --registry remain explicit operator overrides.
    xdg.configFile."codex/lane-index.json".source = indexFile;

    xdg.dataFile."applications/codex-primary-reviewed-resume.desktop".source = primaryDesktop;
    xdg.dataFile."applications/codex-secondary-reviewed-resume.desktop".source = secondaryDesktop;
  };
}
