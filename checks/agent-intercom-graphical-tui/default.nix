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
        inputs.codex-desktop-linux.homeManagerModules.default
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
  claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
  claudeDesktopEntry = configuration.xdg.dataFile."applications/claude-desktop.desktop".source;
  claudeDesktopDefault = builtins.head (
    configuration.xdg.mimeApps.defaultApplications."x-scheme-handler/claude"
  );
  agentIntercom = lib.removeSuffix "/share/agent-intercom/pi" (
    toString configuration.home.file.".pi/agent/packages/agent-intercom-pi".source
  );
in
assert configuration.programs.codexDesktopLinux.enable;
assert configuration.programs.codexDesktopLinux.cliPackage == codexCliPackage;
assert configuration.programs.codexDesktopLinux.remoteControl.package == codexCliPackage;
assert builtins.elem claudeDesktopPackage configuration.home.packages;
assert claudeDesktopEntry == "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
assert claudeDesktopDefault == "claude-desktop.desktop";
assert !smallConfiguration.programs.codexDesktopLinux.enable;
assert !(builtins.elem claudeDesktopPackage smallConfiguration.home.packages);
assert !(smallConfiguration.xdg.dataFile ? "applications/claude-desktop.desktop");
assert !(smallConfiguration.xdg.mimeApps.defaultApplications ? "x-scheme-handler/claude");
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

    test "$(${profile}/bin/codex --version)" = 'codex-cli 0.149.0'
    test "$(${agentIntercom}/bin/codex-raw --version)" = 'codex-cli 0.149.0'
    test "$(${profile}/bin/claude --version)" = '2.1.241 (Claude Code)'
    test -x ${profile}/bin/codex-desktop
    test -x ${profile}/bin/claude-desktop
    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/cci
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude

    test -f ${claudeDesktopEntry}
    grep -Fx 'Exec=claude-desktop %U' ${claudeDesktopEntry}
    grep -Fx 'MimeType=x-scheme-handler/claude' ${claudeDesktopEntry}

    xdg_test="$TMPDIR/claude-xdg"
    mkdir -p "$xdg_test/data/applications" "$xdg_test/config" "$xdg_test/home"
    ln -s ${claudeDesktopEntry} "$xdg_test/data/applications/claude-desktop.desktop"
    update-desktop-database -q "$xdg_test/data/applications"
    grep -Fx 'x-scheme-handler/claude=claude-desktop.desktop;' \
      "$xdg_test/data/applications/mimeinfo.cache"
    cat > "$xdg_test/config/mimeapps.list" <<'EOF'
    [Default Applications]
    x-scheme-handler/claude=${claudeDesktopDefault}
    EOF
    test "$(XDG_DATA_HOME="$xdg_test/data" XDG_CONFIG_HOME="$xdg_test/config" HOME="$xdg_test/home" \
      xdg-mime query default x-scheme-handler/claude)" = "${claudeDesktopDefault}"

    touch "$out"
  ''
