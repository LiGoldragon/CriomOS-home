{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; }));
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix {
    pkgs = homePkgs;
    inherit inputs;
    chatgptCommandLineArgs = "--ozone-platform=wayland";
  };
  mkConfiguration =
    horizon: user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = homePkgs;
      extraSpecialArgs = {
        inherit
          inputs
          horizon
          user
          ownedAgentPackages
          ;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        ({ ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; })
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/agent-intercom.nix
        {
          home = {
            username = "test-user";
            homeDirectory = "/home/test-user";
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  mediumUser = {
    name = "test-user";
    size = {
      min = true;
      medium = true;
    };
  };
  minUser = {
    name = "test-user";
    size.min = true;
  };
  mkHorizon = edge: user: {
    users.test-user = user;
    node = {
      name = "desktop-app-fixture";
      behavesAs.edge = edge;
      services = [ ];
    };
  };
  edgeMedium = mkConfiguration (mkHorizon true mediumUser) mediumUser;
  nonEdgeMedium = mkConfiguration (mkHorizon false mediumUser) mediumUser;
  edgeMin = mkConfiguration (mkHorizon true minUser) minUser;
  profile = pkgs.buildEnv {
    name = "desktop-app-support-profile";
    paths = edgeMedium.home.packages;
  };
  codexCliPackage = ownedAgentPackages.codexPackage;
  claudeCodePackage = ownedAgentPackages.claudeCodePackage;
  claudeDesktopPackage = ownedAgentPackages.claudeDesktopPackage;
  chatgptPackage = ownedAgentPackages.chatgptPackage;
  chatgptCandidate = "${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/codex";
  chatgptWrapperProbeUnwrapped =
    pkgs.runCommand "chatgpt-wrapper-probe-unwrapped"
      {
        passthru.version = "0";
      }
      ''
        mkdir -p "$out/bin" "$out/share"
        printf '%s\n' \
          '#!${pkgs.runtimeShell}' \
          'printf "%s|%s|%s|%s|%s" "''${CODEX_APP_SERVER_USE_LOCAL_DAEMON-}" "''${CODEX_CLI_PATH-}" "''${CODEX_APP_SERVER_FORCE_CLI-}" "''${CODEX_APP_SERVER_CLI_COMMAND-}" "''${CODEX_APP_TOOLS_PIPE_PATH-}" > "$CHATGPT_WRAPPER_PROBE_OUT"' \
          > "$out/bin/chatgpt"
        chmod +x "$out/bin/chatgpt"
      '';
  chatgptWrapperProbe = homePkgs.callPackage ../../owned-agents/chatgpt {
    codexPackage = codexCliPackage;
    chatgpt-unwrapped = chatgptWrapperProbeUnwrapped;
  };
  claudeDesktopEntry = edgeMedium.xdg.dataFile."applications/claude-desktop.desktop".source;
  claudeDesktopDefault = builtins.head (
    edgeMedium.xdg.mimeApps.defaultApplications."x-scheme-handler/claude"
  );
  chatgptEntry = edgeMedium.xdg.dataFile."applications/chatgpt.desktop".source;
  chatgptDefault = builtins.head (
    edgeMedium.xdg.mimeApps.defaultApplications."x-scheme-handler/codex"
  );
  chatgptLauncher = lib.removeSuffix "/share/applications/chatgpt.desktop" (toString chatgptEntry);
in
assert claudeDesktopPackage.passthru.declaredClaudeCode == claudeCodePackage;
assert chatgptPackage.passthru.codexPackage == codexCliPackage;
assert builtins.elem system claudeDesktopPackage.meta.platforms;
assert builtins.elem system chatgptPackage.meta.platforms;
assert claudeDesktopEntry == "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
assert claudeDesktopDefault == "claude-desktop.desktop";
assert chatgptDefault == "chatgpt.desktop";
assert !(nonEdgeMedium.xdg.dataFile ? "applications/claude-desktop.desktop");
assert !(nonEdgeMedium.xdg.mimeApps.defaultApplications ? "x-scheme-handler/claude");
assert !(nonEdgeMedium.xdg.dataFile ? "applications/chatgpt.desktop");
assert !(nonEdgeMedium.xdg.mimeApps.defaultApplications ? "x-scheme-handler/codex");
assert !(edgeMin.xdg.dataFile ? "applications/claude-desktop.desktop");
assert edgeMin.systemd.user.services ? codex-remote-control;
pkgs.runCommand "desktop-app-support-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.binutils
      pkgs.desktop-file-utils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.xdg-utils
      profile
    ];
  }
  ''
    set -eu

    test "$( ${profile}/bin/codex --version )" = 'codex-cli ${codexCliPackage.version}'
    test "$( ${profile}/bin/claude --version )" = '${claudeCodePackage.version} (Claude Code)'
    test -x ${profile}/bin/chatgpt
    test -x ${profile}/bin/claude-desktop

    test -f ${claudeDesktopEntry}
    grep -Fx 'Exec=claude-desktop %U' ${claudeDesktopEntry}
    grep -Fx 'MimeType=x-scheme-handler/claude' ${claudeDesktopEntry}
    test -f ${chatgptEntry}
    grep -E '^Exec=.*chatgpt' ${chatgptEntry}
    grep -F 'x-scheme-handler/codex' ${chatgptEntry}
    test -x ${chatgptLauncher}/bin/chatgpt
    probe_output="$TMPDIR/chatgpt-wrapper-probe"
    CODEX_CLI_PATH=must-not-select-stdio \
      CODEX_APP_SERVER_FORCE_CLI=must-not-select-stdio \
      CODEX_APP_SERVER_CLI_COMMAND=must-not-select-stdio \
      CODEX_APP_TOOLS_PIPE_PATH=must-not-create-private-channel \
      CHATGPT_WRAPPER_PROBE_OUT="$probe_output" \
      ${chatgptWrapperProbe}/bin/chatgpt
    test "$(< "$probe_output")" = '1||||'
    if ! test -x ${chatgptCandidate}; then
      echo "ChatGPT local-daemon resolver candidate is missing: ${chatgptCandidate}" >&2
      exit 1
    fi
    test "$(env -u CODEX_CLI_PATH ${chatgptCandidate} --version)" = 'codex-cli ${codexCliPackage.version}'
    strings ${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/app.asar | grep -F 'getConfigOverrides:()=>[]'

    xdg_test="$TMPDIR/xdg"
    mkdir -p "$xdg_test/data/applications" "$xdg_test/config" "$xdg_test/home"
    ln -s ${claudeDesktopEntry} "$xdg_test/data/applications/claude-desktop.desktop"
    ln -s ${chatgptEntry} "$xdg_test/data/applications/chatgpt.desktop"
    update-desktop-database -q "$xdg_test/data/applications"
    grep -Fx 'x-scheme-handler/claude=claude-desktop.desktop;' \
      "$xdg_test/data/applications/mimeinfo.cache"
    grep -F 'x-scheme-handler/codex=chatgpt.desktop;' \
      "$xdg_test/data/applications/mimeinfo.cache"
    cat > "$xdg_test/config/mimeapps.list" <<'EOF'
    [Default Applications]
    x-scheme-handler/claude=${claudeDesktopDefault}
    x-scheme-handler/codex=${chatgptDefault}
    EOF
    test "$(XDG_DATA_HOME="$xdg_test/data" XDG_CONFIG_HOME="$xdg_test/config" HOME="$xdg_test/home" \
      xdg-mime query default x-scheme-handler/claude)" = "${claudeDesktopDefault}"
    test "$(XDG_DATA_HOME="$xdg_test/data" XDG_CONFIG_HOME="$xdg_test/config" HOME="$xdg_test/home" \
      xdg-mime query default x-scheme-handler/codex)" = "${chatgptDefault}"

    touch "$out"
  ''
