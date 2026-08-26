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
    ];
  }
  ''
    set -eu

    extracted_app="$TMPDIR/claude-desktop-app"
    ${pkgs.asar}/bin/asar extract \
      ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar \
      "$extracted_app"
    runtime_root="$TMPDIR/claude-desktop-runtime"
    mkdir -p "$runtime_root/home" "$runtime_root/config" "$runtime_root/data" "$runtime_root/cache"
    HOME="$runtime_root/home" \
      XDG_CONFIG_HOME="$runtime_root/config" \
      XDG_DATA_HOME="$runtime_root/data" \
      XDG_CACHE_HOME="$runtime_root/cache" \
      ELECTRON_RUN_AS_NODE=1 \
      CRIOMOS_CLAUDE_CODE_MANAGER_HOOK=1 \
      ${claudeDesktopPackage}/bin/claude-desktop \
      ${../agent-intercom-graphical-tui/claude-desktop-runtime-contract.cjs} \
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
      ${../agent-intercom-graphical-tui/claude-desktop-runtime-contract.cjs} \
      "$missing_extracted_app" \
      "$missing_runtime_root/missing-claude" \
      missing

    touch "$out"
  ''
