{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (
    pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; })
  );
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
    CLAUDE_CODE_PATH='${claudeCodePackage}/bin/claude' \
      ${pkgs.nodejs}/bin/node - "$extracted_app" <<'NODE'
    const { readFile, readdir } = require("node:fs/promises");
    const { join } = require("node:path");

    const [appDirectory] = process.argv.slice(2);
    const declaredClaudeCode = process.env.CLAUDE_CODE_PATH;
    const files = [];
    async function collect(directory) {
      for (const entry of await readdir(directory, { withFileTypes: true })) {
        const entryPath = join(directory, entry.name);
        if (entry.isDirectory()) await collect(entryPath);
        else if (entry.isFile() && entry.name.endsWith(".js")) files.push(entryPath);
      }
    }
    function method(source, marker) {
      const start = source.indexOf(marker);
      if (start < 0 || source.indexOf(marker, start + marker.length) >= 0) {
        throw new Error("expected one patched method: " + marker);
      }
      let depth = 0;
      let quote = null;
      let escaped = false;
      const bodyStart = source.indexOf("{", start);
      for (let index = bodyStart; index < source.length; index += 1) {
        const character = source[index];
        if (quote) {
          if (escaped) escaped = false;
          else if (character === "\\") escaped = true;
          else if (character === quote) quote = null;
          continue;
        }
        if (character === "'" || character === '"' || character === "`") {
          quote = character;
          continue;
        }
        if (character === "{") depth += 1;
        if (character === "}" && --depth === 0) return source.slice(start, index + 1);
      }
      throw new Error("unterminated method: " + marker);
    }
    await collect(appDirectory);
    const sources = await Promise.all(files.map((file) => readFile(file, "utf8")));
    const binarySource = sources.find((source) => source.includes("async initLocalBinary(e){"));
    if (!binarySource.includes("this.localBinaryInitPromise=this.initLocalBinary(process.env.CLAUDE_CODE_LOCAL_BINARY)")) {
      throw new Error("Claude Desktop did not activate its local Claude Code override");
    }
    const init = Function("y", "u", "F", "return (" + method(binarySource, "async initLocalBinary(e){").replace(/^async [^(]+/, "async function") + ")")(
      { default: { access: async (path) => { if (path !== declaredClaudeCode) throw new Error("unexpected binary"); } } },
      { constants: { X_OK: 1 } },
      { warn: () => {} },
    );
    const resolved = Function("return (" + method(binarySource, "async resolveHostBinary(){").replace(/^async [^(]+/, "async function") + ")")();
    const state = {};
    await init.call(state, declaredClaudeCode);
    const resolution = await resolved.call({ getLocalBinaryPath: async () => state.localBinaryPath });
    if (state.localBinaryPath !== declaredClaudeCode || resolution.path !== declaredClaudeCode || resolution.resolution !== "local_override") {
      throw new Error("Claude Desktop did not resolve the declared Claude Code executable");
    }
    const failingInit = Function("y", "u", "F", "return (" + method(binarySource, "async initLocalBinary(e){").replace(/^async [^(]+/, "async function") + ")")(
      { default: { access: async () => { throw new Error("missing"); } } },
      { constants: { X_OK: 1 } },
      { warn: () => {} },
    );
    await failingInit.call({}, declaredClaudeCode).then(
      () => { throw new Error("Claude Desktop retained a stateful binary fallback"); },
      () => {},
    );
    const invalidation = method(binarySource, "async invalidateHostBinary(e){");
    const vmPreparation = method(binarySource, "async prepareForVM(e){");
    if (!invalidation.startsWith("async invalidateHostBinary(e){if(process.env.CLAUDE_CODE_LOCAL_BINARY)return;") ||
        !vmPreparation.startsWith("async prepareForVM(e){if(process.env.CLAUDE_CODE_LOCAL_BINARY)throw Error(")) {
      throw new Error("Claude Desktop retained a stateful executable fallback");
    }
    process.env.CLAUDE_CODE_LOCAL_BINARY = declaredClaudeCode;
    const invalidate = Function("return (" + invalidation.replace(/^async [^(]+/, "async function") + ")")();
    const prepareForVM = Function("return (" + vmPreparation.replace(/^async [^(]+/, "async function") + ")")();
    await invalidate.call({});
    await prepareForVM.call({}).then(
      () => { throw new Error("Claude Desktop would materialize its override for a VM"); },
      () => {},
    );
    NODE

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
