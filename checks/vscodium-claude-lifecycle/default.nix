{ inputs, pkgs, ... }:

let
  homePkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
    overlays = [ inputs.pkgs.inputs.nix-vscode-extensions.overlays.default ];
  };
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = homePkgs;
    extraSpecialArgs = {
      inherit inputs;
      hexis = homePkgs.writeShellScriptBin "hexis-fixture" "exit 0";
      textScale.codiumZoom = 0;
      user = {
        preferredEditor = "Emacs";
        size.medium = true;
      };
    };
    modules = [
      ../../modules/home/vscodium/vscodium
      {
        home.username = "vscodium-check";
        home.homeDirectory = "/home/vscodium-check";
        home.stateVersion = "26.05";
      }
    ];
  };
  vscodeConfig = homeConfiguration.config.programs.vscode;
  activation = homeConfiguration.config.home.activation;
  extensionRefresh =
    homeConfiguration.config.home.file.".vscode-oss/extensions/.extensions-immutable.json".onChange;
  lifecycleSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/claude-lifecycle.sh {
    FLOCK = "${pkgs.util-linux}/bin/flock";
    JQ = "${pkgs.jq}/bin/jq";
    READLINK = "${pkgs.coreutils}/bin/readlink";
  };
  lifecycle = pkgs.writeShellScript "criomos-codium-claude-lifecycle-fixture" (
    builtins.readFile lifecycleSource
  );
  extA = pkgs.runCommand "claude-extension-fixture-a" { } ''
    mkdir -p $out
    printf '{"version":"2.1.215"}\n' > $out/package.json
  '';
  extB = pkgs.runCommand "claude-extension-fixture-b" { } ''
    mkdir -p $out
    printf '{"version":"2.1.215"}\n' > $out/package.json
  '';
  extC = pkgs.runCommand "claude-extension-fixture-c" { } ''
    mkdir -p $out
    printf '{"version":"2.1.214"}\n' > $out/package.json
  '';
in
assert vscodeConfig.package.pname == homePkgs.vscodium.pname;
assert vscodeConfig.package.version == homePkgs.vscodium.version;
assert vscodeConfig.package.meta.mainProgram == "codium";
assert homePkgs.lib.getExe vscodeConfig.package == "${vscodeConfig.package}/bin/codium";
assert vscodeConfig.nameShort == "VSCodium";
assert vscodeConfig.dataFolderName == ".vscode-oss";
assert homePkgs.lib.hasInfix
  (builtins.unsafeDiscardStringContext "${vscodeConfig.package}/bin/codium --list-extensions")
  (builtins.unsafeDiscardStringContext extensionRefresh);
assert activation.bootstrapMutableClaudeCodeExtension.before == [ "linkGeneration" ];
assert builtins.match ".*--bootstrap.*" activation.bootstrapMutableClaudeCodeExtension.data != null;
assert activation.replaceMutableClaudeCodeExtension.after == [ "linkGeneration" ];
assert builtins.match ".*--activate.*" activation.replaceMutableClaudeCodeExtension.data != null;
pkgs.runCommand "vscodium-claude-lifecycle-check" { } ''
  set -euxo pipefail
  echo STAGE=setup
  blocked_activate() {
    ${pkgs.util-linux}/bin/setsid "${lifecycle}" --activate >/dev/null 2>&1 & activation_pid=$!
    sleep 1
    kill -TERM -- "-$activation_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL -- "-$activation_pid" 2>/dev/null || true
    wait "$activation_pid" 2>/dev/null || true
  }
  home="$TMPDIR/home"; ext="$home/.vscode-oss/extensions"; state="$home/state"; roots="$home/roots"
    mkdir -p "$ext" "$state" "$roots"
    export CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots"
    ln -s ${extA} "$ext/anthropic.claude-code"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-bootstrap
    tree_before=$(find -P "$ext" "$roots" -printf '%p %y %l\n' | sort)
    "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-ready
    test "$tree_before" = "$(find -P "$ext" "$roots" -printf '%p %y %l\n' | sort)"
    "${lifecycle}" --activate
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extA})"
    test -L "$roots/anthropic.claude-code-2.1.215-linux-x64"
    before=$(sha256sum "$state/manifest")
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --dry-run >/dev/null
    test "$before" = "$(sha256sum "$state/manifest")"
    rm "$ext/anthropic.claude-code"; ln -s ${extB} "$ext/anthropic.claude-code"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extB})"
    rm "$ext/anthropic.claude-code-2.1.215-linux-x64"
    mkdir "$ext/anthropic.claude-code-2.1.215-linux-x64"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate >/dev/null 2>&1 || true
    test -d "$ext/anthropic.claude-code-2.1.215-linux-x64"
    rm -rf "$ext/anthropic.claude-code-2.1.215-linux-x64"; ln -s ${extB} "$ext/anthropic.claude-code-2.1.215-linux-x64"
    printf 'v1\nmanaged\t2.1.215\tanthropic.claude-code-2.1.215-linux-x64\t/nix/store/not-the-link\n' > "$state/manifest"
    "${lifecycle}" --activate >/dev/null 2>&1 || true
    test -L "$ext/anthropic.claude-code-2.1.215-linux-x64"
    test -e "$roots/anthropic.claude-code-2.1.215-linux-x64"
    rm "$ext/anthropic.claude-code"; ln -s ${extC} "$ext/anthropic.claude-code"; rm -f "$state/manifest"
    rm -f "$ext/anthropic.claude-code-2.1.215-linux-x64" "$roots/anthropic.claude-code-2.1.215-linux-x64"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-bootstrap
    "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-ready
    "${lifecycle}" --activate
    test -L "$ext/anthropic.claude-code-2.1.214-linux-x64"
    test ! -e "$ext/anthropic.claude-code-2.1.215-linux-x64"
    # A held shared lease blocks mutation; releasing it allows reconciliation.
    exec 9>"$state/lifecycle.lock"
    ${pkgs.util-linux}/bin/flock -s 9
    { find -P "$ext" "$roots" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/lease.before"
  blocked_activate
    { find -P "$ext" "$roots" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/lease.after"
    diff -u "$TMPDIR/lease.before" "$TMPDIR/lease.after"
    exec 9>&-
    # Exercise the managed-launcher lease with a blocking fake Codium. The
    # intermediate target changes after READY but is outside the observed
    # discovery tree, so an unlocked reconciler is the only possible mutation.
    managed_target="$TMPDIR/managed-target"
    rm "$ext/anthropic.claude-code"
    ln -s ${extC} "$managed_target"
    ln -s "$managed_target" "$ext/anthropic.claude-code"
    fake="$TMPDIR/fake-codium"; printf '#!%s\nprintf READY > %s\nsleep 30\n' "${pkgs.runtimeShell}" "$TMPDIR/codium.ready" > "$fake"; chmod +x "$fake"
    launcher="$TMPDIR/managed-launcher"; cat > "$launcher" <<EOF
  #!${pkgs.runtimeShell}
  exec 9>"$state/lifecycle.lock"
  ${pkgs.util-linux}/bin/flock -x 9
  CRIOMOS_VSCODIUM_LOCK_HELD=1 "${lifecycle}" --launch
  ${pkgs.util-linux}/bin/flock -s 9
  exec "$fake"
  EOF
    chmod +x "$launcher"
    rm -f "$TMPDIR/codium.ready"
    ${pkgs.util-linux}/bin/setsid "$launcher" >/dev/null 2>&1 & launcher_pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$TMPDIR/codium.ready" ] && break; sleep 0.1; done
    test -e "$TMPDIR/codium.ready"
    find -P "$ext" -printf '%p %y %l\n' | sort > "$TMPDIR/discovery.before"
    find -P "$roots" -printf '%p %y %l\n' | sort > "$TMPDIR/roots.before"
    cp "$state/manifest" "$TMPDIR/manifest.before"
    rm "$managed_target"; ln -s ${extA} "$managed_target"
  blocked_activate
    find -P "$ext" -printf '%p %y %l\n' | sort > "$TMPDIR/discovery.after"
    find -P "$roots" -printf '%p %y %l\n' | sort > "$TMPDIR/roots.after"
    cp "$state/manifest" "$TMPDIR/manifest.after"
    diff -u "$TMPDIR/discovery.before" "$TMPDIR/discovery.after"
    diff -u "$TMPDIR/roots.before" "$TMPDIR/roots.after"
    diff -u "$TMPDIR/manifest.before" "$TMPDIR/manifest.after"
    ${pkgs.procps}/bin/pkill -TERM -P "$launcher_pid" 2>/dev/null || true
    kill -TERM -- "-$launcher_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL -- "-$launcher_pid" 2>/dev/null || true
    wait "$launcher_pid" 2>/dev/null || true
    "${lifecycle}" --activate >/dev/null 2>&1
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extA})"
    test ! -e "$ext/anthropic.claude-code-2.1.214-linux-x64"
    echo STAGE=complete
    touch "$out"
''
