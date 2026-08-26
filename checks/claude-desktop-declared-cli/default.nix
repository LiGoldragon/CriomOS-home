{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (
    pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; })
  );
  claudeCodePackage = homePkgs.callPackage ../../packages/claude-code { inherit inputs; };
  claudeDesktopPackage = homePkgs.claudeDesktopWithDeclaredClaudeCode {
    claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
    inherit claudeCodePackage;
  };
in
assert claudeDesktopPackage.passthru.declaredClaudeCode == claudeCodePackage;
pkgs.runCommand "claude-desktop-declared-cli-contract"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.coreutils
      pkgs.dbus
      pkgs.nodejs
      pkgs.xauth
      pkgs.xvfb
    ];
  }
  ''
    set -eu

    prepare_test_app() {
      test_desktop="$TMPDIR/claude-desktop-$1"
      test_app="$TMPDIR/claude-desktop-app-$1"
      cp -a ${claudeDesktopPackage}/. "$test_desktop"
      chmod -R u+w "$test_desktop"
      ${pkgs.asar}/bin/asar extract \
        ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar \
        "$test_app"
      ${pkgs.nodejs}/bin/node -e '
        const fs = require("node:fs");
        const path = require("node:path");
        const app = process.argv[1];
        const packagePath = path.join(app, "package.json");
        const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));
        packageJson.main = "criomos-runtime-bootstrap.cjs";
        fs.writeFileSync(packagePath, JSON.stringify(packageJson));
        fs.writeFileSync(
          path.join(app, "criomos-runtime-bootstrap.cjs"),
          "require(process.env.CRIOMOS_CLAUDE_DESKTOP_RUNTIME_CONTRACT)\\n",
        );
      ' "$test_app"
      ${pkgs.asar}/bin/asar pack \
        "$test_app" \
        "$test_desktop/lib/claude-desktop/resources/app.asar"
    }

    echo 'claude-desktop-declared-cli: valid override'
    prepare_test_app valid
    runtime_root="$TMPDIR/claude-desktop-runtime"
    mkdir -p "$runtime_root/home" "$runtime_root/config" "$runtime_root/data" "$runtime_root/cache"
    timeout --kill-after=5s 60s dbus-run-session \
      --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
      xvfb-run -a env \
      HOME="$runtime_root/home" \
      XDG_CONFIG_HOME="$runtime_root/config" \
      XDG_DATA_HOME="$runtime_root/data" \
      XDG_CACHE_HOME="$runtime_root/cache" \
      CRIOMOS_CLAUDE_DESKTOP_RUNTIME_CONTRACT=${../agent-intercom-graphical-tui/claude-desktop-runtime-contract.cjs} \
      CRIOMOS_CLAUDE_DESKTOP_TEST_APP="$test_app" \
      CRIOMOS_CLAUDE_DESKTOP_TEST_MODE=valid \
      CLAUDE_CODE_LOCAL_BINARY=${claudeCodePackage}/bin/claude \
      "$test_desktop/lib/claude-desktop/claude-desktop"

    echo 'claude-desktop-declared-cli: missing override'
    prepare_test_app missing
    missing_runtime_root="$TMPDIR/claude-desktop-runtime-missing"
    mkdir -p "$missing_runtime_root/home" "$missing_runtime_root/config" "$missing_runtime_root/data" "$missing_runtime_root/cache"
    timeout --kill-after=5s 60s dbus-run-session \
      --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
      xvfb-run -a env \
      HOME="$missing_runtime_root/home" \
      XDG_CONFIG_HOME="$missing_runtime_root/config" \
      XDG_DATA_HOME="$missing_runtime_root/data" \
      XDG_CACHE_HOME="$missing_runtime_root/cache" \
      CRIOMOS_CLAUDE_DESKTOP_RUNTIME_CONTRACT=${../agent-intercom-graphical-tui/claude-desktop-runtime-contract.cjs} \
      CRIOMOS_CLAUDE_DESKTOP_TEST_APP="$test_app" \
      CRIOMOS_CLAUDE_DESKTOP_TEST_MODE=missing \
      CLAUDE_CODE_LOCAL_BINARY="$missing_runtime_root/missing-claude" \
      "$test_desktop/lib/claude-desktop/claude-desktop"

    echo 'claude-desktop-declared-cli: passed'
    touch "$out"
  ''
