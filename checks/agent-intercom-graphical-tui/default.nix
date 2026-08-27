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
  baseHorizon = {
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
      pkgs = homePkgs;
      extraSpecialArgs = {
        inherit inputs user ownedAgentPackages;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = baseHorizon // {
          users.test-user = user;
        };
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
  codexCliPackage = ownedAgentPackages.codexPackage;
  codexDesktopGate = ownedAgentPackages.chatgptPackage.passthru.codexDesktopGate;
  claudeCodePackage = ownedAgentPackages.claudeCodePackage;
  claudeDesktopPackage = ownedAgentPackages.claudeDesktopPackage;
  chatgptPackage = ownedAgentPackages.chatgptPackage;
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
assert claudeDesktopPackage.passthru.declaredClaudeCode == claudeCodePackage;
assert chatgptPackage.version == chatgptPackage.unwrapped.version;
assert chatgptPackage.passthru.codexPackage == codexCliPackage;
assert chatgptPackage.passthru.commandLineArgs == "--ozone-platform=wayland";
assert claudeDesktopEntry == "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
assert claudeDesktopDefault == "claude-desktop.desktop";
assert chatgptEntry == "${chatgptLauncher}/share/applications/chatgpt.desktop";
assert chatgptDefault == "chatgpt.desktop";
assert !(smallConfiguration.xdg.dataFile ? "applications/claude-desktop.desktop");
assert !(smallConfiguration.xdg.mimeApps.defaultApplications ? "x-scheme-handler/claude");
assert !(smallConfiguration.xdg.dataFile ? "applications/chatgpt.desktop");
assert !(smallConfiguration.xdg.mimeApps.defaultApplications ? "x-scheme-handler/codex");
assert configuration.systemd.user.services ? codex-remote-control;
assert !(configuration.systemd.user.services ? agent-intercom-codex-bridge);
pkgs.runCommand "agent-intercom-graphical-tui-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.desktop-file-utils
      pkgs.gnugrep
      pkgs.gnused
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
    ! grep -F '${chatgptPackage}/bin/chatgpt' ${chatgptLauncher}/bin/chatgpt
    chatgpt_wrapped_path="$(sed -n -E 's|.*(/nix/store/[^ ]+/bin/chatgpt).*|\1|p' ${chatgptLauncher}/bin/chatgpt | head -n 1)"
    test -n "$chatgpt_wrapped_path"
    grep -F -- '--ozone-platform=wayland' ${chatgptPackage}/bin/chatgpt
    grep -Fx 'unset CODEX_CLI_PATH' ${chatgptLauncher}/bin/chatgpt
    grep -Fx 'unset CODEX_APP_SERVER_FORCE_CLI' ${chatgptLauncher}/bin/chatgpt
    grep -Fx 'unset CODEX_CLI_PATH' ${chatgptPackage}/bin/chatgpt
    grep -Fx 'unset CODEX_APP_SERVER_FORCE_CLI' ${chatgptPackage}/bin/chatgpt
    test -L ${chatgptPackage.unwrapped}/lib/chatgpt/resources/codex
    test "$(readlink -f ${chatgptPackage.unwrapped}/lib/chatgpt/resources/codex)" = '${codexDesktopGate}/bin/codex'

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
