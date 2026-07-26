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
  nixStoreFixture = pkgs.writeShellScript "nix-store-fixture" ''
    set -euf
    [ "$#" -eq 4 ]
    [ "$1" = --add-root ]
    root="$2"
    [ "$3" = --realise ]
    target="$4"
    case "$target" in /nix/store/*) ;; *) exit 1;; esac
    store_name="''${target#/nix/store/}"
    store_name="''${store_name%%/*}"
    ${pkgs.coreutils}/bin/ln -s "/nix/store/$store_name" "$root.tmp.$$"
    ${pkgs.coreutils}/bin/mv -Tf "$root.tmp.$$" "$root"
  '';
  fakeCodium = pkgs.writeShellScript "codium-registry-and-daemon-fixture" ''
    set -euf
    if [ "''${1:-}" = --list-extensions ]; then
      [ "''${FAKE_CODIUM_FAIL:-0}" != 1 ] || exit 1
      if ${pkgs.util-linux}/bin/flock -xn "$FAKE_LOCK" true; then
        ${pkgs.coreutils}/bin/touch "$FAKE_SYSTEMD_DIR/refresh-gap"
      fi
      registry="$CRIOMOS_VSCODIUM_EXTENSIONS_DIR/extensions.json"
      ${pkgs.jq}/bin/jq --arg path "$CRIOMOS_VSCODIUM_EXTENSIONS_DIR/anthropic.claude-code-2.1.215-linux-x64" \
        '[.[] | select(.identifier.id? != "anthropic.claude-code")] + [{identifier:{id:"anthropic.claude-code"},location:{path:$path}}]' \
        "$CRIOMOS_VSCODIUM_REGISTRY_BACKUP" > "$registry"
      exit 0
    fi
    if [ "''${1:-}" = --version ]; then
      ${pkgs.coreutils}/bin/touch "$FAKE_SYSTEMD_DIR/version.called"
      exit 0
    fi
    (${pkgs.coreutils}/bin/sleep "''${FAKE_APP_SECONDS:-2}") & child_a=$!
    (${pkgs.coreutils}/bin/sleep "''${FAKE_APP_SECONDS:-2}") & child_b=$!
    printf '%s\n%s\n' "$child_a" "$child_b" > "$FAKE_SYSTEMD_DIR/$FAKE_SCOPE.child"
    ${pkgs.coreutils}/bin/touch "$FAKE_SYSTEMD_DIR/app.started"
  '';
  fakeSystemctl = pkgs.writeShellScript "systemctl-user-scope-fixture" ''
    set -euf
    dir="$FAKE_SYSTEMD_DIR"
    case "''${2:-}" in
      show)
        unit="''${3:-}"
        child="$dir/$unit.child"
        state=inactive
        if [ -s "$child" ]; then
          while IFS= read -r pid; do
            kill -0 "$pid" 2>/dev/null && state=active
          done < "$child"
        elif [ -s "$dir/$unit.session" ]; then
          IFS= read -r session < "$dir/$unit.session"
          if [ ! -e "$session/started" ]; then
            ${pkgs.coreutils}/bin/touch "$dir/$unit.pending"
            state=activating
          elif [ ! -e "$session/completed" ]; then
            state=active
          fi
        fi
        printf '%s\n' "$state"
        ;;
      stop)
        shift 2
        for unit in "$@"; do
          for pid_file in "$dir/$unit.child" "$dir/$unit.pid"; do
            if [ -s "$pid_file" ]; then
              while IFS= read -r pid; do kill "$pid" 2>/dev/null || true; done < "$pid_file"
            fi
          done
        done
        ;;
    esac
  '';
  fakeSystemdRun = pkgs.writeShellScript "systemd-run-user-scope-fixture" ''
    set -euf
    scope=0 unit=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --scope) scope=1; shift ;;
        --unit=*) unit="''${1#--unit=}"; shift ;;
        --property=*) shift ;;
        --user|--collect|--quiet|--no-block) shift ;;
        *) break ;;
      esac
    done
    [ -n "$unit" ] && [ "$#" -gt 0 ]
    if [ "$scope" -eq 1 ]; then
      printf '%s\n' "$2" > "$FAKE_SYSTEMD_DIR/$unit.session"
      # Keep the queued state observable: the first status probe accepts the
      # scope, publishes `activating`, then lets its command begin.
      (
        while [ ! -e "$FAKE_SYSTEMD_DIR/$unit.pending" ]; do
          ${pkgs.coreutils}/bin/sleep 0.01
        done
        FAKE_SCOPE="$unit" "$@"
      ) >/dev/null 2>&1 &
    else
      # The parent launcher already holds SH after its atomic EX→SH
      # conversion. An EX probe here witnesses that there was no handoff gap.
      ${pkgs.util-linux}/bin/flock -xn "$FAKE_LOCK" true || true
      if ${pkgs.util-linux}/bin/flock -xn "$FAKE_LOCK" true; then
        ${pkgs.coreutils}/bin/touch "$FAKE_SYSTEMD_DIR/handoff-gap"
      fi
      "$@" >/dev/null 2>&1 &
      printf '%s\n' "$!" > "$FAKE_SYSTEMD_DIR/$unit.pid"
    fi
  '';
  lifecycleSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/claude-lifecycle.sh {
    COREUTILS = "${pkgs.coreutils}";
    FLOCK = "${pkgs.util-linux}/bin/flock";
    AWK = "${pkgs.gawk}/bin/awk";
    GREP = "${pkgs.gnugrep}/bin/grep";
    JQ = "${pkgs.jq}/bin/jq";
    NIX_STORE = "${pkgs.nix}/bin/nix-store";
    PGREP = "${pkgs.procps}/bin/pgrep";
    READLINK = "${pkgs.coreutils}/bin/readlink";
    SED = "${pkgs.gnused}/bin/sed";
    CODIUM = "${homePkgs.vscodium}/bin/codium";
    SYSTEMCTL = "${pkgs.systemd}/bin/systemctl";
    SLEEP = "${pkgs.coreutils}/bin/sleep";
  };
  lifecycle = pkgs.writeShellScript "criomos-codium-claude-lifecycle-fixture" (
    builtins.readFile lifecycleSource
  );
  scopeSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/codium-scope.sh {
    COREUTILS = "${pkgs.coreutils}";
    CODIUM = "${homePkgs.vscodium}/bin/codium";
    READLINK = "${pkgs.coreutils}/bin/readlink";
  };
  scopeRunner = pkgs.writeShellScript "criomos-codium-scope-fixture" (builtins.readFile scopeSource);
  launcherSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/codium-launch.sh {
    COREUTILS = "${pkgs.coreutils}";
    FLOCK = "${pkgs.util-linux}/bin/flock";
    LIFECYCLE = "${lifecycle}";
    SCOPE_RUNNER = "${scopeRunner}";
    SYSTEMD_RUN = "${pkgs.systemd}/bin/systemd-run";
    SYSTEMCTL = "${pkgs.systemd}/bin/systemctl";
    DATE = "${pkgs.coreutils}/bin/date";
    READLINK = "${pkgs.coreutils}/bin/readlink";
    SLEEP = "${pkgs.coreutils}/bin/sleep";
  };
  launcher = pkgs.writeShellScript "criomos-codium-launch-fixture" (builtins.readFile launcherSource);
  extA = pkgs.runCommand "claude-extension-fixture-a" { } ''
    mkdir -p $out/extension
    printf '{"version":"2.1.215"}\n' > $out/extension/package.json
  '';
  extB = pkgs.runCommand "claude-extension-fixture-b" { } ''
    mkdir -p $out/extension
    printf '{"version":"2.1.215"}\n' > $out/extension/package.json
  '';
  extC = pkgs.runCommand "claude-extension-fixture-c" { } ''
    mkdir -p $out/extension
    printf '{"version":"2.1.214"}\n' > $out/extension/package.json
  '';
  extAPath = "${extA}/extension";
  extBPath = "${extB}/extension";
  extCPath = "${extC}/extension";
in
assert vscodeConfig.package.pname == homePkgs.vscodium.pname;
assert vscodeConfig.package.version == homePkgs.vscodium.version;
assert vscodeConfig.package.meta.mainProgram == "codium";
assert homePkgs.lib.getExe vscodeConfig.package == "${vscodeConfig.package}/bin/codium";
assert vscodeConfig.nameShort == "VSCodium";
assert vscodeConfig.dataFolderName == ".vscode-oss";
assert homePkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "--activation-refresh") (
  builtins.unsafeDiscardStringContext extensionRefresh
);
assert
  !(homePkgs.lib.hasInfix (builtins.unsafeDiscardStringContext "${vscodeConfig.package}/bin/codium --list-extensions") (
    builtins.unsafeDiscardStringContext extensionRefresh
  ));
assert activation.bootstrapMutableClaudeCodeExtension.before == [ "linkGeneration" ];
assert builtins.match ".*--bootstrap.*" activation.bootstrapMutableClaudeCodeExtension.data != null;
assert activation.replaceMutableClaudeCodeExtension.after == [ "linkGeneration" ];
assert builtins.match ".*--activate.*" activation.replaceMutableClaudeCodeExtension.data != null;
pkgs.runCommand "vscodium-claude-lifecycle-check" { } ''
  set -euxo pipefail
  test "$(id -u)" -ne 0
  for runtime_script in "${lifecycleSource}" "${scopeSource}" "${launcherSource}"; do
    ${pkgs.bash}/bin/bash -n "$runtime_script"
    ! ${pkgs.gnugrep}/bin/grep -E \
      '(^|[;|&[:space:]])(awk|flock|readlink|realpath|mkdir|mktemp|mv|rm|ln|rmdir|cp|sed|grep|cut|tr|stat|systemd-run|systemctl|sleep|date|nix-store|codium|cat|head|tail|wc|pgrep)([;|&[:space:]]|$)' \
      "$runtime_script"
  done
  echo STAGE=setup
  blocked_activate() {
    ${pkgs.util-linux}/bin/setsid "${lifecycle}" --activate >/dev/null 2>&1 & activation_pid=$!
    sleep 1
    kill -TERM -- "-$activation_pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL -- "-$activation_pid" 2>/dev/null || true
    wait "$activation_pid" 2>/dev/null || true
  }
  home="$TMPDIR/home"; ext="$home/.vscode-oss/extensions"; state="$home/state"; roots="$state/gcroots"
    mkdir -p "$ext" "$state" "$roots"
    export CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" CRIOMOS_VSCODIUM_LOCK_FILE="$state/lifecycle.lock"
    # Runtime defaults are store paths. Fakes cross only the three external
    # boundaries; the lifecycle, launcher, scope runner, and their filesystem
    # tools must remain runnable when activation supplies no useful PATH.
    export CRIOMOS_VSCODIUM_NIX_STORE="${nixStoreFixture}"
    export CRIOMOS_VSCODIUM_CODIUM="${fakeCodium}"
    export CRIOMOS_VSCODIUM_SYSTEMCTL="${fakeSystemctl}"
    export CRIOMOS_VSCODIUM_SYSTEMD_RUN="${fakeSystemdRun}"
    path_guard_cwd="$TMPDIR/path-guard-cwd"
    path_guard_sentinel="$TMPDIR/path-guard-sentinel"
    mkdir -p "$path_guard_cwd" "$path_guard_sentinel"
    printf preserved > "$path_guard_sentinel/content"
    assert_path_rejected() {
      label="$1"
      shift
      rm -rf "$path_guard_cwd/state" "$path_guard_cwd/.local" "$path_guard_cwd/.vscode-oss"
      if (cd "$path_guard_cwd" && env "$@" PATH=/nonexistent "${lifecycle}" --activate); then false; fi
      test "$(cat "$path_guard_sentinel/content")" = preserved
      test ! -e "$path_guard_cwd/state"
      test ! -e "$path_guard_cwd/.local"
      test ! -e "$path_guard_cwd/.vscode-oss"
    }
    # Every path boundary must fail before the lifecycle can create relative
    # state in its cwd or alter an external sentinel.
    assert_path_rejected home-relative \
      -u CRIOMOS_VSCODIUM_EXTENSIONS_DIR -u CRIOMOS_VSCODIUM_STATE_DIR \
      -u CRIOMOS_VSCODIUM_GCROOT_DIR -u CRIOMOS_VSCODIUM_LOCK_FILE \
      -u XDG_STATE_HOME HOME=relative
    assert_path_rejected home-empty \
      -u CRIOMOS_VSCODIUM_EXTENSIONS_DIR -u CRIOMOS_VSCODIUM_STATE_DIR \
      -u CRIOMOS_VSCODIUM_GCROOT_DIR -u CRIOMOS_VSCODIUM_LOCK_FILE \
      -u XDG_STATE_HOME HOME=
    assert_path_rejected xdg-relative -u CRIOMOS_VSCODIUM_STATE_DIR HOME="$home" XDG_STATE_HOME=relative
    assert_path_rejected xdg-empty -u CRIOMOS_VSCODIUM_STATE_DIR HOME="$home" XDG_STATE_HOME=
    assert_path_rejected extensions-relative CRIOMOS_VSCODIUM_EXTENSIONS_DIR=relative
    assert_path_rejected extensions-empty CRIOMOS_VSCODIUM_EXTENSIONS_DIR=
    assert_path_rejected state-relative CRIOMOS_VSCODIUM_STATE_DIR=relative
    assert_path_rejected state-empty CRIOMOS_VSCODIUM_STATE_DIR=
    assert_path_rejected root-relative CRIOMOS_VSCODIUM_GCROOT_DIR=relative
    assert_path_rejected root-empty CRIOMOS_VSCODIUM_GCROOT_DIR=
    assert_path_rejected lock-relative CRIOMOS_VSCODIUM_LOCK_FILE=relative
    assert_path_rejected lock-empty CRIOMOS_VSCODIUM_LOCK_FILE=
    assert_path_rejected state-control CRIOMOS_VSCODIUM_STATE_DIR=$'bad\nstate'
    test "$(cat "$path_guard_sentinel/content")" = preserved
    ln -s ${extAPath} "$ext/anthropic.claude-code"
    # Exercise activation without a GC-root override. The lifecycle itself runs
    # as this unprivileged builder and must keep its visible root in user state;
    # the old /nix/var/nix/gcroots/per-user default would fail before the
    # daemon-root fixture could be invoked.
    unprivileged_home="$TMPDIR/unprivileged-home"
    unprivileged_ext="$unprivileged_home/.vscode-oss/extensions"
    unprivileged_state="$unprivileged_home/state"
    mkdir -p "$unprivileged_ext" "$unprivileged_state"
    ln -s ${extAPath} "$unprivileged_ext/anthropic.claude-code"
    (
      unset CRIOMOS_VSCODIUM_GCROOT_DIR CRIOMOS_VSCODIUM_LOCK_FILE
      export HOME="$unprivileged_home" USER=vscodium-check
      export CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$unprivileged_ext"
      export CRIOMOS_VSCODIUM_STATE_DIR="$unprivileged_state"
      export CRIOMOS_VSCODIUM_LOCK_FILE="$unprivileged_state/lifecycle.lock"
      "${lifecycle}" --activate
      test "$(head -n1 "$unprivileged_state/manifest")" = v1-bootstrap
      "${lifecycle}" --activate
      "${lifecycle}" --activate
    )
    test -L "$unprivileged_state/gcroots/anthropic.claude-code-2.1.215-linux-x64"
    test "$(readlink -f "$unprivileged_state/gcroots/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extA})"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-bootstrap
    tree_before=$(find -P "$ext" "$roots" -printf '%p %y %l\n' | sort)
    "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-ready
    test "$tree_before" = "$(find -P "$ext" "$roots" -printf '%p %y %l\n' | sort)"
    "${lifecycle}" --activate
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extAPath})"
    test -L "$roots/anthropic.claude-code-2.1.215-linux-x64"
    before=$(sha256sum "$state/manifest")
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --dry-run >/dev/null
    test "$before" = "$(sha256sum "$state/manifest")"
    rm "$ext/anthropic.claude-code"; ln -s ${extBPath} "$ext/anthropic.claude-code"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extBPath})"
    rm "$ext/anthropic.claude-code-2.1.215-linux-x64"
    mkdir "$ext/anthropic.claude-code-2.1.215-linux-x64"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate >/dev/null 2>&1 || true
    test -d "$ext/anthropic.claude-code-2.1.215-linux-x64"
    rm -rf "$ext/anthropic.claude-code-2.1.215-linux-x64"; ln -s ${extBPath} "$ext/anthropic.claude-code-2.1.215-linux-x64"
    printf 'v1\nmanaged\t2.1.215\tanthropic.claude-code-2.1.215-linux-x64\t/nix/store/not-the-link\n' > "$state/manifest"
    rm -f "$roots/anthropic.claude-code-2.1.215-linux-x64"
    "${lifecycle}" --activate >/dev/null 2>&1 || true
    test -L "$ext/anthropic.claude-code-2.1.215-linux-x64"
    test ! -e "$roots/anthropic.claude-code-2.1.215-linux-x64"
    rm "$ext/anthropic.claude-code"; ln -s ${extCPath} "$ext/anthropic.claude-code"; rm -f "$state/manifest"
    rm -f "$ext/anthropic.claude-code-2.1.215-linux-x64" "$roots/anthropic.claude-code-2.1.215-linux-x64"
    CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$ext" CRIOMOS_VSCODIUM_STATE_DIR="$state" CRIOMOS_VSCODIUM_GCROOT_DIR="$roots" "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-bootstrap
    "${lifecycle}" --activate
    test "$(head -n1 "$state/manifest")" = v1-ready
    "${lifecycle}" --activate
    test -L "$ext/anthropic.claude-code-2.1.214-linux-x64"
    test ! -e "$ext/anthropic.claude-code-2.1.215-linux-x64"
    test ! -e "$roots/anthropic.claude-code-2.1.215-linux-x64"
    # A held shared lease blocks mutation; releasing it allows reconciliation.
    exec 9>"$state/lifecycle.lock"
    ${pkgs.util-linux}/bin/flock -s 9
    { find -P "$ext" "$roots" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/lease.before"
    # A Home activation under a live GUI lease must defer immediately rather
    # than block for the session's whole lifetime.
    activation_started=$(${pkgs.coreutils}/bin/date +%s%N)
    "${lifecycle}" --activate
    env PATH=/nonexistent "${lifecycle}" --activation-refresh
    activation_elapsed=$(($(${pkgs.coreutils}/bin/date +%s%N) - activation_started))
    test "$activation_elapsed" -lt 1000000000
  blocked_activate
    { find -P "$ext" "$roots" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/lease.after"
    diff -u "$TMPDIR/lease.before" "$TMPDIR/lease.after"
    exec 9>&-
    # Exercise the managed-launcher lease with a blocking fake Codium. The
    # intermediate target changes after READY but is outside the observed
    # discovery tree, so an unlocked reconciler is the only possible mutation.
    managed_target="$TMPDIR/managed-target"
    rm "$ext/anthropic.claude-code"
    ln -s ${extCPath} "$managed_target"
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
    rm "$managed_target"; ln -s ${extAPath} "$managed_target"
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
    test "$(readlink -f "$ext/anthropic.claude-code-2.1.215-linux-x64")" = "$(readlink -f ${extAPath})"
    test ! -e "$ext/anthropic.claude-code-2.1.214-linux-x64"
    # The immutable extension declaration remains unchanged when only Codium's
    # mutable registry has a stale same-version location.  Launch must use the
    # supported underlying Codium refresh, retain unmanaged entries, and hand
    # off its shared lease without a window for an exclusive reconciler.
    fake_systemd="$TMPDIR/fake-systemd"
    mkdir -p "$fake_systemd"
    export FAKE_SYSTEMD_DIR="$fake_systemd" FAKE_LOCK="$state/lifecycle.lock" FAKE_APP_SECONDS=5
    watch_sentinel="$TMPDIR/watch-sentinel"
    mkdir -p "$watch_sentinel"
    printf preserved > "$watch_sentinel/content"
    mkdir -p "$state/session.12345678/nested" "$TMPDIR/foreign/session.12345678"
    ln -s "$watch_sentinel" "$state/session.ABCDEFGH"
    assert_watch_scope_path_rejected() {
      if "${lifecycle}" --watch-scope criomos-vscodium-1-1.scope "$1"; then false; fi
      test "$(cat "$watch_sentinel/content")" = preserved
    }
    assert_watch_scope_path_rejected "$state/session.12345678/../watch-sentinel/ready"
    assert_watch_scope_path_rejected "$state/session.12345678/nested/ready"
    assert_watch_scope_path_rejected "$TMPDIR/foreign/session.12345678/ready"
    assert_watch_scope_path_rejected "$state/session.ABCDEFGH/ready"
    assert_watch_scope_path_rejected "$state/session.abc$'\n'1234/ready"
    test "$(cat "$watch_sentinel/content")" = preserved
    rm -rf "$state/session.12345678" "$state/session.ABCDEFGH" "$TMPDIR/foreign"
    immutable="$ext/.extensions-immutable.json"
    printf '{"managed":"unchanged"}\n' > "$immutable"
    cp "$immutable" "$TMPDIR/immutable.before"
    printf '%s\n' "[{\"identifier\":{\"id\":\"anthropic.claude-code\"},\"location\":{\"path\":\"$ext/anthropic.claude-code-2.1.198-linux-x64\"}},{\"identifier\":{\"id\":\"unmanaged.fixture\"},\"location\":{\"path\":\"$ext/unmanaged.fixture\"}}]" > "$ext/extensions.json"
    "${lifecycle}" --activation-refresh
    test ! -e "$fake_systemd/refresh-gap"
    ${pkgs.jq}/bin/jq -e --arg path "$ext/anthropic.claude-code-2.1.215-linux-x64" \
      'any(.[]; .identifier.id == "anthropic.claude-code" and .location.path == $path)' "$ext/extensions.json"
    ${pkgs.jq}/bin/jq 'map(if .identifier.id == "anthropic.claude-code" then .location.path = "'$ext'/anthropic.claude-code-2.1.198-linux-x64" else . end)' \
      "$ext/extensions.json" > "$ext/extensions.json.tmp"
    mv "$ext/extensions.json.tmp" "$ext/extensions.json"
    unmanaged_before=$(${pkgs.jq}/bin/jq -c '[.[] | select(.identifier.id == "unmanaged.fixture")]' "$ext/extensions.json" | sha256sum)
    env PATH=/nonexistent "${launcher}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$fake_systemd/app.started" ] && break; sleep 0.1; done
    test -e "$fake_systemd/app.started"
    pending_scopes=("$fake_systemd"/criomos-vscodium-*.scope.pending)
    test -e "''${pending_scopes[0]}"
    test ! -e "$fake_systemd/handoff-gap"
    cmp "$TMPDIR/immutable.before" "$immutable"
    ${pkgs.jq}/bin/jq -e --arg path "$ext/anthropic.claude-code-2.1.215-linux-x64" \
      'any(.[]; .identifier.id == "anthropic.claude-code" and .location.path == $path)' "$ext/extensions.json"
    unmanaged_after=$(${pkgs.jq}/bin/jq -c '[.[] | select(.identifier.id == "unmanaged.fixture")]' "$ext/extensions.json" | sha256sum)
    test "$unmanaged_before" = "$unmanaged_after"
    ! ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    child_file=$(find "$fake_systemd" -name 'criomos-vscodium-*.scope.child')
    child_a=$(sed -n '1p' "$child_file")
    child_b=$(sed -n '2p' "$child_file")
    kill "$child_a"
    sleep 0.3
    ! ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    kill "$child_b"
    for _ in 1 2 3 4 5 6 7 8 9 10; do ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true && break; sleep 0.1; done
    ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q .
    # A CLI-like Codium command may exit before the watcher's first probe. Its
    # scope runner's durable started/completed acknowledgement must still let
    # the wrapper return promptly, then reclaim its one-shot session state.
    rm -f "$fake_systemd/version.called"
    cli_started=$(${pkgs.coreutils}/bin/date +%s%N)
    "${launcher}" --version
    cli_elapsed=$(($(${pkgs.coreutils}/bin/date +%s%N) - cli_started))
    test "$cli_elapsed" -lt 1000000000
    test -e "$fake_systemd/version.called"
    for _ in 1 2 3 4 5 6 7 8 9 10; do ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q . && break; sleep 0.1; done
    ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q .
    # A failed supported refresh restores the original registry and no GUI
    # scope survives: launch is fail-closed rather than running with drift.
    cp "$ext/extensions.json" "$TMPDIR/registry.before-failure"
    ${pkgs.jq}/bin/jq 'map(if .identifier.id == "anthropic.claude-code" then .location.path = "'$ext'/anthropic.claude-code-2.1.198-linux-x64" else . end)' \
      "$ext/extensions.json" > "$ext/extensions.json.tmp"
    mv "$ext/extensions.json.tmp" "$ext/extensions.json"
    cp "$ext/extensions.json" "$TMPDIR/registry.stale-before-failure"
    rm -f "$fake_systemd/app.started"
    if FAKE_CODIUM_FAIL=1 "${launcher}"; then false; fi
    cmp "$TMPDIR/registry.stale-before-failure" "$ext/extensions.json"
    test ! -e "$fake_systemd/app.started"
    # A manifest is user-controlled state.  Every malformed name must stop
    # reconciliation before it can retarget the managed link/root or reach a
    # cleanup path.  The traversal form below was accepted by the old glob and
    # points both cleanup operands outside their managed directories.
    tamper_sentinel="$home/manifest-tamper-sentinel"
    mkdir -p "$tamper_sentinel"
    printf preserved > "$tamper_sentinel/content"
    traversal_base="anthropic.claude-code-2.1.214-linux-x64"
    mkdir -p "$ext/$traversal_base" "$roots/$traversal_base"
    ln -s ${extCPath} "$home/.vscode-oss/outside-linux-x64"
    ln -s ${extCPath} "$home/outside-linux-x64"
    nested_base="anthropic.claude-code-2.1.213-linux-x64"
    mkdir -p "$ext/$nested_base" "$roots/$nested_base"
    ln -s ${extCPath} "$ext/$nested_base/nested-linux-x64"
    ln -s ${extCPath} "$roots/$nested_base/nested-linux-x64"
    cr_name=$'anthropic.claude-code-2.1.212\r-linux-x64'
    ln -s ${extCPath} "$ext/$cr_name"
    ln -s ${extCPath} "$roots/$cr_name"
    nul_name="anthropic.claude-code-2.1.211-linux-x64"
    ln -s ${extCPath} "$ext/$nul_name"
    ln -s ${extCPath} "$roots/$nul_name"
    assert_tampered_manifest_ignored() {
      label="$1" name="$2"
      printf 'v1\nmanaged\t2.1.214\t%s\t%s\n' "$name" "${extCPath}" > "$state/manifest"
      cp "$state/manifest" "$TMPDIR/manifest-$label.before"
      { find -P "$ext" "$roots" "$tamper_sentinel" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/tamper-$label.before"
      "${lifecycle}" --activate
      cmp "$TMPDIR/manifest-$label.before" "$state/manifest"
      { find -P "$ext" "$roots" "$tamper_sentinel" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/tamper-$label.after"
      diff -u "$TMPDIR/tamper-$label.before" "$TMPDIR/tamper-$label.after"
      test "$(cat "$tamper_sentinel/content")" = preserved
    }
    assert_tampered_manifest_ignored traversal "$traversal_base/../../outside-linux-x64"
    test -L "$home/.vscode-oss/outside-linux-x64"
    test -L "$home/outside-linux-x64"
    test "$(readlink "$home/.vscode-oss/outside-linux-x64")" = "${extCPath}"
    test "$(readlink "$home/outside-linux-x64")" = "${extCPath}"
    assert_tampered_manifest_ignored nested "$nested_base/nested-linux-x64"
    assert_tampered_manifest_ignored absolute "/$traversal_base"
    assert_tampered_manifest_ignored carriage-return "$cr_name"
    assert_tampered_manifest_ignored newline $'anthropic.claude-code-2.1.214-linux-x64\n'
    printf 'v1\nmanaged\t2.1.211\t%s\0\t%s\n' "$nul_name" "${extCPath}" > "$state/manifest"
    cp "$state/manifest" "$TMPDIR/manifest-nul.before"
    { find -P "$ext" "$roots" "$tamper_sentinel" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/tamper-nul.before"
    "${lifecycle}" --activate
    cmp "$TMPDIR/manifest-nul.before" "$state/manifest"
    { find -P "$ext" "$roots" "$tamper_sentinel" -printf '%p %y %l\n' | sort; cat "$state/manifest"; } > "$TMPDIR/tamper-nul.after"
    diff -u "$TMPDIR/tamper-nul.before" "$TMPDIR/tamper-nul.after"
    test -L "$ext/$nul_name"
    test -L "$roots/$nul_name"
    echo STAGE=complete
    touch "$out"
''
