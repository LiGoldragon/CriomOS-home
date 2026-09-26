{ inputs, pkgs, ... }:
let
  homePkgs = pkgs;
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  claudeCodePackage = ownedAgentPackages.claudeCodePackage;
  claudeDesktopPackage = ownedAgentPackages.claudeDesktopPackage;
in
pkgs.runCommand "claude-desktop-launcher-linkage"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.coreutils
      pkgs.dbus
      pkgs.nodejs
      pkgs.util-linux
      pkgs.xvfb
    ];
  }
  ''
    set -eu

    test_desktop="$TMPDIR/claude-desktop"
    test_app="$TMPDIR/claude-desktop-app"
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
      packageJson.main = "criomos-launcher-linkage.cjs";
      fs.writeFileSync(packagePath, JSON.stringify(packageJson));
      fs.writeFileSync(path.join(app, "criomos-launcher-linkage.cjs"), `
        const electron = require("electron");
        const expectedResources = process.env.CRIOMOS_EXPECTED_RESOURCES;
        const expectedExecutable = process.env.CRIOMOS_EXPECTED_EXECUTABLE;
        if (!expectedResources || !expectedExecutable) throw new Error("launcher linkage expectations are absent");
        electron.app.whenReady().then(() => {
          if (process.resourcesPath !== expectedResources) throw new Error("launcher used " + process.resourcesPath + ", expected " + expectedResources);
          if (process.execPath !== expectedExecutable) throw new Error("launcher used " + process.execPath + ", expected " + expectedExecutable);
          if (process.env.CLAUDE_CODE_LOCAL_BINARY !== undefined) throw new Error("launcher unexpectedly sets a mutable CLI override");
          console.log("claude-desktop-launcher-linkage: passed");
          electron.app.quit();
          process.exit(0);
        }).catch((error) => {
          console.error(error?.stack || error);
          electron.app.quit();
          process.exit(1);
        });
      `);
    ' "$test_app"
    ${pkgs.asar}/bin/asar pack \
      "$test_app" \
      "$test_desktop/lib/claude-desktop/resources/app.asar"
    launcher="$test_desktop/bin/claude-desktop"
    sed -i "s|${claudeDesktopPackage}|$test_desktop|g" "$launcher"
    ! grep -F '/nix/store/' "$launcher" | grep -F '/bin/claude-desktop' | grep -v "$test_desktop" 
    if test -e "$test_desktop/bin/.claude-desktop-wrapped"; then
      echo 'claude-desktop-launcher-linkage: nested wrapper remains' >&2
      exit 1
    fi

    ${pkgs.xvfb}/bin/Xvfb :99 -screen 0 1024x768x24 -nolisten tcp &
    xvfb_pid=$!
    launcher_pgid=""
    cleanup() {
      result=$?
      if test -n "$launcher_pgid"; then
        kill -TERM -- "-$launcher_pgid" 2>/dev/null || true
        kill -KILL -- "-$launcher_pgid" 2>/dev/null || true
      fi
      kill "$xvfb_pid" 2>/dev/null || true
      exit "$result"
    }
    trap cleanup EXIT
    for attempt in $(seq 1 20); do
      test -S /tmp/.X11-unix/X99 && break
      sleep 0.1
    done
    test -S /tmp/.X11-unix/X99

    runtime_root="$TMPDIR/runtime"
    mkdir -p "$runtime_root/home" "$runtime_root/config" "$runtime_root/data" "$runtime_root/cache"
    setsid timeout --kill-after=5s 20s dbus-run-session \
      --config-file=${pkgs.dbus}/share/dbus-1/session.conf \
      env DISPLAY=:99 \
      HOME="$runtime_root/home" \
      XDG_CONFIG_HOME="$runtime_root/config" \
      XDG_DATA_HOME="$runtime_root/data" \
      XDG_CACHE_HOME="$runtime_root/cache" \
      CRIOMOS_EXPECTED_RESOURCES="$test_desktop/lib/claude-desktop/resources" \
      CRIOMOS_EXPECTED_EXECUTABLE="$test_desktop/lib/claude-desktop/claude-desktop" \
      "$test_desktop/bin/claude-desktop" \
      --disable-gpu \
      --disable-software-rasterizer &
    launcher_pgid=$!
    wait "$launcher_pgid"
    launcher_pgid=""

    touch "$out"
  ''
