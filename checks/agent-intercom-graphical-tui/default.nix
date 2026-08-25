{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  horizon = {
    node = {
      name = "graphical-tui-contract";
      services = [
        { AgentIntercomLocal = { }; }
        { AgentIntercomGraphical = { }; }
      ];
    };
  };
  mkConfiguration =
    user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs horizon user;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
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
    size.medium = true;
  };
  smallUser = {
    name = "test-user";
    size.min = true;
  };
  configuration = mkConfiguration mediumUser;
  smallConfiguration = mkConfiguration smallUser;
  profile = pkgs.buildEnv {
    name = "agent-intercom-graphical-tui-profile";
    paths = configuration.home.packages;
  };
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
  claudeCodePackage = pkgs.callPackage ../../packages/claude-code { inherit inputs; };
  claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
  chatgptPackage = inputs.llm-agents.packages.${system}.chatgpt;
  claudeDesktopEntry = configuration.xdg.dataFile."applications/claude-desktop.desktop".source;
  claudeDesktopDefault = builtins.head (
    configuration.xdg.mimeApps.defaultApplications."x-scheme-handler/claude"
  );
  chatgptEntry = configuration.xdg.dataFile."applications/chatgpt.desktop".source;
  chatgptDefault = builtins.head (
    configuration.xdg.mimeApps.defaultApplications."x-scheme-handler/codex"
  );
  chatgptLauncher = lib.removeSuffix "/share/applications/chatgpt.desktop" (toString chatgptEntry);
  agentIntercom = lib.removeSuffix "/share/agent-intercom/pi" (
    toString configuration.home.file.".pi/agent/packages/agent-intercom-pi".source
  );
in
assert builtins.elem claudeDesktopPackage configuration.home.packages;
assert chatgptPackage.version == "26.818.61809";
assert claudeDesktopEntry == "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
assert claudeDesktopDefault == "claude-desktop.desktop";
assert chatgptEntry == "${chatgptLauncher}/share/applications/chatgpt.desktop";
assert chatgptDefault == "chatgpt.desktop";
assert !(smallConfiguration.xdg.dataFile ? "applications/claude-desktop.desktop");
assert !(smallConfiguration.xdg.mimeApps.defaultApplications ? "x-scheme-handler/claude");
assert !(smallConfiguration.xdg.dataFile ? "applications/chatgpt.desktop");
assert !(smallConfiguration.xdg.mimeApps.defaultApplications ? "x-scheme-handler/codex");
assert !(configuration.systemd.user.services ? codex-remote-control);
assert !(configuration.systemd.user.services ? agent-intercom-codex-bridge);
pkgs.runCommand "agent-intercom-graphical-tui-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.desktop-file-utils
      pkgs.gnugrep
      pkgs.nodejs
      pkgs.xdg-utils
      profile
      agentIntercom
    ];
  }
  ''
    set -eu

    test "$(${profile}/bin/codex --version)" = 'codex-cli ${codexCliPackage.version}'
    test "$(${agentIntercom}/bin/codex-raw --version)" = 'codex-cli ${codexCliPackage.version}'
    test "$(${profile}/bin/claude --version)" = '${claudeCodePackage.version} (Claude Code)'
    test -x ${profile}/bin/chatgpt
    ! test -e ${profile}/bin/codex-desktop
    test -x ${profile}/bin/claude-desktop
    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/cci
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude

    test -f ${claudeDesktopEntry}
    grep -Fx 'Exec=claude-desktop %U' ${claudeDesktopEntry}
    grep -Fx 'MimeType=x-scheme-handler/claude' ${claudeDesktopEntry}

    test -f ${chatgptEntry}
    grep -E '^Exec=.*chatgpt' ${chatgptEntry}
    grep -F 'x-scheme-handler/codex' ${chatgptEntry}
    test -x ${chatgptLauncher}/bin/chatgpt
    grep -F '${chatgptPackage}/bin/chatgpt' ${chatgptLauncher}/bin/chatgpt
    grep -F 'CODEX_CLI_PATH' ${chatgptLauncher}/bin/chatgpt
    grep -F '${codexCliPackage}/bin/codex' ${chatgptLauncher}/bin/chatgpt

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
