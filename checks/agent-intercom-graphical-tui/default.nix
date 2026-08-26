{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; }));
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
      pkgs = homePkgs;
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
  codexCliPackage = homePkgs.callPackage ../../packages/codex { inherit inputs; };
  claudeCodePackage = homePkgs.callPackage ../../packages/claude-code { inherit inputs; };
  claudeDesktopPackage = homePkgs.claudeDesktopWithDeclaredClaudeCode {
    claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
    inherit claudeCodePackage;
  };
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
assert claudeDesktopPackage.passthru.declaredClaudeCode == claudeCodePackage;
assert chatgptPackage.version == "26.820.60940";
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
      pkgs.asar
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

    extracted_app="$TMPDIR/claude-desktop-app"
    ${pkgs.asar}/bin/asar extract \
      ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar \
      "$extracted_app"
    ${pkgs.gnugrep}/bin/grep -Fq 'CLAUDE_CODE_LOCAL_BINARY' ${claudeDesktopPackage}/bin/claude-desktop
    runtime_root="$TMPDIR/claude-desktop-runtime"
    mkdir -p "$runtime_root/home" "$runtime_root/config" "$runtime_root/data" "$runtime_root/cache"
    HOME="$runtime_root/home" \
      XDG_CONFIG_HOME="$runtime_root/config" \
      XDG_DATA_HOME="$runtime_root/data" \
      XDG_CACHE_HOME="$runtime_root/cache" \
      ELECTRON_RUN_AS_NODE=1 \
      CRIOMOS_CLAUDE_CODE_MANAGER_HOOK=1 \
      ${claudeDesktopPackage}/bin/claude-desktop \
      ${./claude-desktop-runtime-contract.cjs} \
      "$extracted_app" \
      ${claudeCodePackage}/bin/claude \
      valid

    missing_runtime_root="$TMPDIR/claude-desktop-runtime-missing"
    missing_extracted_app="$TMPDIR/claude-desktop-app-missing"
    mkdir -p "$missing_runtime_root/home" "$missing_runtime_root/config" "$missing_runtime_root/data" "$missing_runtime_root/cache"
    ${pkgs.asar}/bin/asar extract \
      ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar \
      "$missing_extracted_app"
    HOME="$missing_runtime_root/home" \
      XDG_CONFIG_HOME="$missing_runtime_root/config" \
      XDG_DATA_HOME="$missing_runtime_root/data" \
      XDG_CACHE_HOME="$missing_runtime_root/cache" \
      ELECTRON_RUN_AS_NODE=1 \
      CRIOMOS_CLAUDE_CODE_MANAGER_HOOK=1 \
      CLAUDE_CODE_LOCAL_BINARY="$missing_runtime_root/missing-claude" \
      ${claudeDesktopPackage}/lib/claude-desktop/claude-desktop \
      ${./claude-desktop-runtime-contract.cjs} \
      "$missing_extracted_app" \
      "$missing_runtime_root/missing-claude" \
      missing

    test -f ${chatgptEntry}
    grep -E '^Exec=.*chatgpt' ${chatgptEntry}
    grep -F 'x-scheme-handler/codex' ${chatgptEntry}
    test -x ${chatgptLauncher}/bin/chatgpt
    ! grep -F '${chatgptPackage}/bin/chatgpt' ${chatgptLauncher}/bin/chatgpt
    chatgpt_wrapped_path="$(sed -n -E 's|.*(/nix/store/[^ ]+/bin/chatgpt).*|\1|p' ${chatgptLauncher}/bin/chatgpt | head -n 1)"
    test -n "$chatgpt_wrapped_path"
    grep -F -- '--ozone-platform=wayland' "$chatgpt_wrapped_path"
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
