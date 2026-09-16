{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; };
    modules = [
      inputs.stylix.homeModules.stylix
      ../../modules/home/profiles/min/codex-layer-resume.nix
      {
        home = {
          username = "codex-layer-resume-check";
          homeDirectory = "/home/codex-layer-resume-check";
          stateVersion = "26.05";
        };
        stylix.base16Scheme = ../../modules/home/ignis.yaml;
        criomosHome.codexLayerResume.enable = true;
      }
    ];
  };
  configuration = homeConfiguration.config;
  packageName = candidate: pkgs.lib.getName candidate;
  package = builtins.head (
    builtins.filter (
      candidate: (candidate.pname or "") == "codex-layer-resume"
    ) configuration.home.packages
  );
  primaryTerminal = builtins.head (
    builtins.filter (
      candidate: packageName candidate == "codex-primary-terminal"
    ) configuration.home.packages
  );
  secondaryTerminal = builtins.head (
    builtins.filter (
      candidate: packageName candidate == "codex-secondary-terminal"
    ) configuration.home.packages
  );
  indexFile = configuration.xdg.configFile."codex/lane-index.json".source;
  primaryDesktop =
    configuration.xdg.dataFile."applications/codex-primary-reviewed-resume.desktop".source;
  secondaryDesktop =
    configuration.xdg.dataFile."applications/codex-secondary-reviewed-resume.desktop".source;
in
pkgs.runCommand "codex-layer-resume"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.nodejs
      pkgs.ghostty
    ];
  }
  ''
    set -eu

    # Run the upstream package's behavioral tests from the packaged copy.
    package_root="$TMPDIR/package"
    mkdir -p "$package_root/test"
    cp ${package}/share/codex-layer-resume/codex-layer-resume.mjs "$package_root/"
    cp ${package}/share/codex-layer-resume/codex-layer-resume.test.mjs "$package_root/"
    cp ${package}/share/codex-layer-resume/codex-lane-index.json "$package_root/"
    cp ${package}/share/codex-layer-resume/test/codex-lane-index.test.mjs "$package_root/test/"
    node --test "$package_root/codex-layer-resume.test.mjs" "$package_root/test/codex-lane-index.test.mjs"

    # Exercise the installed shell wrappers against a supplied codex mock. This
    # observes the exact resume argv without starting a Codex session.
    mock_bin="$TMPDIR/mock-bin"
    explicit_registry="$TMPDIR/explicit-lane-index.json"
    mkdir -p "$mock_bin"
    cp ${indexFile} "$explicit_registry"
    cat > "$mock_bin/codex" <<'MOCK'
    #!/bin/sh
    set -eu
    printf '%s\n' "$@" > "$MOCK_LOG"
    MOCK
    chmod 0755 "$mock_bin/codex"

    export MOCK_LOG="$TMPDIR/primary-argv"
    export PATH="$mock_bin:$PATH"
    ${package}/bin/codex-primary --registry "$explicit_registry"
    test "$(sed -n '1p' "$MOCK_LOG")" = resume
    test "$(sed -n '2p' "$MOCK_LOG")" = 01a0a715-2d5d-7342-b278-1dbcf78795bd

    export MOCK_LOG="$TMPDIR/secondary-argv"
    ${package}/bin/codex-secondary --registry "$explicit_registry"
    test "$(sed -n '1p' "$MOCK_LOG")" = resume
    test "$(sed -n '2p' "$MOCK_LOG")" = 01a0a11f-6130-70e2-80b1-796348e7b086

    # An explicit registry wins over CODEX_LAYER_INDEX and the default path.
    export CODEX_LAYER_INDEX="$TMPDIR/does-not-exist.json"
    export MOCK_LOG="$TMPDIR/explicit-argv"
    ${package}/bin/codex-primary --registry "$explicit_registry"
    test "$(sed -n '2p' "$MOCK_LOG")" = 01a0a715-2d5d-7342-b278-1dbcf78795bd

    # The pending successor is deliberately absent from the reviewed snapshot.
    ! grep -F 01a0aacb-ac84-71a1-88a0-05ed9961ca9d ${indexFile}

    # The terminal launchers use a new Ghostty surface and an explicit palette.
    grep -F -- '--gtk-single-instance=false' ${primaryTerminal}/bin/codex-primary-terminal
    grep -F -- '--class=net.criome.codex-layer' ${primaryTerminal}/bin/codex-primary-terminal
    grep -F -- '--config-file=' ${primaryTerminal}/bin/codex-primary-terminal
    grep -F -- '--title="Codex Primary — reviewed resume"' ${primaryTerminal}/bin/codex-primary-terminal
    grep -F -- '--config-file=' ${secondaryTerminal}/bin/codex-secondary-terminal
    theme_file="$(sed -n 's/.*--config-file=\([^ ]*\).*/\1/p' ${primaryTerminal}/bin/codex-primary-terminal | head -n 1)"
    test -n "$theme_file"
    ${pkgs.ghostty}/bin/ghostty +validate-config --config-file="$theme_file"

    # Desktop entries point at those fresh-terminal launchers.
    grep -F 'Exec=' ${primaryDesktop}
    grep -F 'Exec=' ${secondaryDesktop}
    grep -F 'Terminal=false' ${primaryDesktop}
    grep -F 'Terminal=false' ${secondaryDesktop}

    touch "$out"
  ''
