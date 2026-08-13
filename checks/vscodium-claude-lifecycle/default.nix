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
  fakeCodium = pkgs.writeShellScript "codium-registry-and-supervisor-fixture" ''
    set -euf
    if [ "''${1:-}" = --list-extensions ]; then
      [ "''${FAKE_CODIUM_FAIL:-0}" != 1 ] || exit 1
      if ${pkgs.util-linux}/bin/flock -xn "$FAKE_LOCK" true; then
        ${pkgs.coreutils}/bin/touch "$FAKE_LAUNCH_DIR/refresh-gap"
      fi
      registry="$CRIOMOS_VSCODIUM_EXTENSIONS_DIR/extensions.json"
      immutable="$CRIOMOS_VSCODIUM_EXTENSIONS_DIR/.extensions-immutable.json"
      if [ "''${FAKE_CODIUM_SCAN_FILESYSTEM:-0}" = 1 ]; then
        immutable_claude_version="$(${pkgs.jq}/bin/jq -er \
          '.[] | select(.identifier.id == "anthropic.claude-code") | .version' "$immutable")"
        immutable_openai_version="$(${pkgs.jq}/bin/jq -er \
          '.[] | select(.identifier.id == "openai.chatgpt") | .version' "$immutable")"
        desired_claude="anthropic.claude-code-$immutable_claude_version-linux-x64"
        discovery="$FAKE_LAUNCH_DIR/refresh-discovery"
        : > "$discovery"
        while IFS= read -r -d "" candidate; do
          candidate_target="$(${pkgs.coreutils}/bin/readlink -f "$candidate")"
          ${pkgs.jq}/bin/jq -e --arg version "$immutable_claude_version" \
            '(.publisher | ascii_downcase) == "anthropic"
             and .name == "claude-code"
             and .version == $version' \
            "$candidate_target/package.json" >/dev/null
          printf 'claude %s %s\n' "''${candidate##*/}" "$candidate_target" >> "$discovery"
        done < <(
          ${pkgs.findutils}/bin/find -P "$CRIOMOS_VSCODIUM_EXTENSIONS_DIR" \
            -maxdepth 1 -type l -name 'anthropic.claude-code-*-linux-x64' -print0 \
            | LC_ALL=C ${pkgs.coreutils}/bin/sort -z
        )
        ${pkgs.gnugrep}/bin/grep -Fq "claude $desired_claude " "$discovery"
        openai_target="$(${pkgs.coreutils}/bin/readlink -f \
          "$CRIOMOS_VSCODIUM_EXTENSIONS_DIR/openai.chatgpt")"
        ${pkgs.jq}/bin/jq -e --arg version "$immutable_openai_version" \
          '.publisher == "openai" and .name == "chatgpt" and .version == $version' \
          "$openai_target/package.json" >/dev/null
        printf 'openai openai.chatgpt %s\n' "$openai_target" >> "$discovery"
      fi
      ${pkgs.jq}/bin/jq \
        --arg ext_dir "$CRIOMOS_VSCODIUM_EXTENSIONS_DIR" \
        '. as $registry
         | input as $immutable
         | [$registry[] | . as $entry
            | select($immutable | all(.[];
                .identifier.id? != $entry.identifier.id?
              ))]
           + [$immutable[]
              | .identifier.id as $id
              | (if $id == "anthropic.claude-code"
                 then $ext_dir + "/anthropic.claude-code-" + .version + "-linux-x64"
                 else $ext_dir + "/" + .relativeLocation
                 end) as $path
              | .location.path = $path
              | .location.fsPath = $path
              | .relativeLocation = ($path | split("/") | last)]' \
        "$CRIOMOS_VSCODIUM_REGISTRY_BACKUP" "$immutable" > "$registry"
      exit 0
    fi
    if [ "''${1:-}" = --version ]; then
      printf '%s\n' "''${FAKE_CODIUM_CLI_OUTPUT:-fixture-version}"
      ${pkgs.coreutils}/bin/touch "$FAKE_LAUNCH_DIR/version.called"
      exit "''${FAKE_CODIUM_CLI_STATUS:-0}"
    fi
    if [ "''${1:-}" = --status ]; then
      printf '%s\n' "''${FAKE_CODIUM_CLI_OUTPUT:-fixture-status}"
      exit "''${FAKE_CODIUM_CLI_STATUS:-0}"
    fi
    [ "''${FAKE_CODIUM_CLOSE_FD9:-0}" != 1 ] || exec 9>&-
    printf '%s\n' "$$" > "$FAKE_LAUNCH_DIR/codium.pid"
    printf '%s\n' "$PPID" > "$FAKE_LAUNCH_DIR/supervisor.pid"
    test "$(<"/proc/$$/cgroup")" = "$(<"/proc/$PPID/cgroup")"
    test "$(<"/proc/$$/cgroup")" = "$FAKE_CALLER_CGROUP"
    ! ${pkgs.gnugrep}/bin/grep -q criomos-vscodium "/proc/$$/cgroup"
    (${pkgs.coreutils}/bin/sleep "''${FAKE_APP_SECONDS:-2}") & child_a=$!
    (${pkgs.coreutils}/bin/sleep "''${FAKE_APP_SECONDS:-2}") & child_b=$!
    printf '%s\n%s\n' "$child_a" "$child_b" > "$FAKE_LAUNCH_DIR/children"
    terminate() {
      kill "$child_a" "$child_b" 2>/dev/null || true
      wait "$child_a" "$child_b" 2>/dev/null || true
      exit 143
    }
    trap terminate INT TERM HUP
    printf '%s\n' launch >> "$FAKE_LAUNCH_DIR/app.launches"
    ${pkgs.coreutils}/bin/touch "$FAKE_LAUNCH_DIR/app.started"
    wait "$child_a" "$child_b"
  '';
  fakeNotifier = pkgs.writeShellScript "vscodium-launch-notifier-fixture" ''
    set -euf
    printf '%s\n' "$*" >> "$FAKE_LAUNCH_DIR/notifier.calls"
  '';
  lifecycleSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/claude-lifecycle.sh {
    COREUTILS = "${pkgs.coreutils}";
    DIFFUTILS = "${pkgs.diffutils}";
    FLOCK = "${pkgs.util-linux}/bin/flock";
    GREP = "${pkgs.gnugrep}/bin/grep";
    JQ = "${pkgs.jq}/bin/jq";
    NIX_STORE = "${pkgs.nix}/bin/nix-store";
    PGREP = "${pkgs.procps}/bin/pgrep";
    READLINK = "${pkgs.coreutils}/bin/readlink";
    SED = "${pkgs.gnused}/bin/sed";
    CODIUM = "${homePkgs.vscodium}/bin/codium";
  };
  lifecycleClosure = pkgs.symlinkJoin {
    name = "criomos-codium-claude-lifecycle-fixture";
    paths = [
      (pkgs.writeShellScriptBin "criomos-codium-claude-lifecycle" (builtins.readFile lifecycleSource))
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.nix
      pkgs.procps
      pkgs.util-linux
    ];
  };
  lifecycle = "${lifecycleClosure}/bin/criomos-codium-claude-lifecycle";
  supervisorSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/codium-supervisor.sh {
    COREUTILS = "${pkgs.coreutils}";
    CODIUM = "${homePkgs.vscodium}/bin/codium";
    READLINK = "${pkgs.coreutils}/bin/readlink";
    SLEEP = "${pkgs.coreutils}/bin/sleep";
  };
  supervisor = pkgs.writeShellScript "criomos-codium-supervisor-fixture" (
    builtins.readFile supervisorSource
  );
  launcherSource = pkgs.replaceVars ../../modules/home/vscodium/vscodium/codium-launch.sh {
    COREUTILS = "${pkgs.coreutils}";
    CODIUM = "${homePkgs.vscodium}/bin/codium";
    FLOCK = "${pkgs.util-linux}/bin/flock";
    LIFECYCLE = "${lifecycle}";
    NOTIFY_SEND = "${fakeNotifier}";
    SUPERVISOR = "${supervisor}";
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
  extD = pkgs.runCommand "claude-extension-fixture-d" { } ''
    mkdir -p $out/extension
    printf '{"version":"2.1.220"}\n' > $out/extension/package.json
  '';
  extE = pkgs.runCommand "claude-extension-fixture-e" { } ''
    mkdir -p $out/extension
    printf '{"version":"2.1.223"}\n' > $out/extension/package.json
  '';
  transitionPreviousVersion = "7.8.9";
  transitionCurrentVersion = "7.9.0";
  transitionLegacyAliasVersion = "7.7.0";
  transitionOpenaiVersion = "30.1.0";
  transitionPreviousOpenaiVersion = "29.9.0";
  transitionPreviousExt = pkgs.runCommand "claude-extension-transition-previous-fixture" { } ''
    mkdir -p $out/extension
    printf '{"name":"claude-code","publisher":"Anthropic","version":"${transitionPreviousVersion}"}\n' > $out/extension/package.json
  '';
  transitionCurrentExt = pkgs.runCommand "claude-extension-transition-current-fixture" { } ''
    mkdir -p $out/extension
    printf '{"name":"claude-code","publisher":"Anthropic","version":"${transitionCurrentVersion}"}\n' > $out/extension/package.json
  '';
  adversarialExt = pkgs.runCommand "claude-extension-adversarial-fixture" { } ''
    mkdir -p $out/extension
    printf '{"name":"claude-code","publisher":"Foreign","version":"${transitionPreviousVersion}"}\n' > $out/extension/package.json
  '';
  transitionOpenaiExt = pkgs.runCommand "openai-extension-transition-fixture" { } ''
    mkdir -p $out/extension
    printf '{"name":"chatgpt","publisher":"openai","version":"${transitionOpenaiVersion}"}\n' > $out/extension/package.json
  '';
  immutableCurrent = pkgs.writeText "vscodium-immutable-current-fixture.json" ''
    [{"identifier":{"id":"anthropic.claude-code"},"version":"${transitionCurrentVersion}","relativeLocation":"anthropic.claude-code"},{"identifier":{"id":"openai.chatgpt"},"version":"${transitionOpenaiVersion}","relativeLocation":"openai.chatgpt"}]
  '';
  foreignRoot = pkgs.runCommand "vscodium-claude-foreign-root-fixture" { } ''
    mkdir -p $out
    printf foreign > $out/sentinel
  '';
  extAPath = "${extA}/extension";
  extBPath = "${extB}/extension";
  extCPath = "${extC}/extension";
  extDPath = "${extD}/extension";
  extEPath = "${extE}/extension";
  transitionPreviousExtPath = "${transitionPreviousExt}/extension";
  transitionCurrentExtPath = "${transitionCurrentExt}/extension";
  adversarialExtPath = "${adversarialExt}/extension";
  transitionOpenaiExtPath = "${transitionOpenaiExt}/extension";
in
assert vscodeConfig.package.pname == homePkgs.vscodium.pname;
assert vscodeConfig.package.version == homePkgs.vscodium.version;
assert vscodeConfig.package.meta.mainProgram == "codium";
assert homePkgs.lib.getExe vscodeConfig.package == "${vscodeConfig.package}/bin/codium";
assert vscodeConfig.nameShort == "VSCodium";
assert vscodeConfig.dataFolderName == ".vscode-oss";
assert builtins.any (
  extension: extension.version == "26.5803.61601"
) vscodeConfig.profiles.default.extensions;
assert builtins.any (
  extension: extension.version == "2.1.231"
) vscodeConfig.profiles.default.extensions;
assert activation.bootstrapMutableClaudeCodeExtension.before == [ "linkGeneration" ];
assert builtins.match ".*--bootstrap.*" activation.bootstrapMutableClaudeCodeExtension.data != null;
assert activation.replaceMutableClaudeCodeExtension.after == [ "linkGeneration" ];
assert builtins.match ".*--activate.*" activation.replaceMutableClaudeCodeExtension.data != null;
assert activation.refreshMutableClaudeCodeRegistry.after == [ "replaceMutableClaudeCodeExtension" ];
assert
  builtins.match ".*--activation-refresh.*" activation.refreshMutableClaudeCodeRegistry.data != null;
pkgs.runCommand "vscodium-claude-lifecycle-check" { } ''
  set -euxo pipefail
  test "$(id -u)" -ne 0
  # The marketplace metadata controls Home Manager's immutable extension
  # declaration.  It must match each locked VSIX manifest: a stale metadata
  # version leaves a newer managed extension beside an older immutable record,
  # which correctly makes the activation lifecycle fail closed.
  test "$(
    ${pkgs.unzip}/bin/unzip -p ${inputs.claude-code-vsix} extension/package.json \
      | ${pkgs.jq}/bin/jq -er .version
  )" = 2.1.231
  test "$(
    ${pkgs.unzip}/bin/unzip -p ${inputs.claude-code-vsix} extension/package.json \
      | ${pkgs.jq}/bin/jq -er '.engines.vscode'
  )" = '^1.94.0'
  test "$(
    ${pkgs.unzip}/bin/unzip -p ${inputs.codex-chatgpt-vsix} extension/package.json \
      | ${pkgs.jq}/bin/jq -er .version
  )" = 26.5803.61601
  test "$(
    ${pkgs.unzip}/bin/unzip -p ${inputs.codex-chatgpt-vsix} extension/package.json \
      | ${pkgs.jq}/bin/jq -er '.engines.vscode'
  )" = '^1.96.2'
  test "$(printf '%s\n' 1.94.0 ${homePkgs.vscodium.version} | sort -V | head -n1)" = 1.94.0
  test "$(printf '%s\n' 1.96.2 ${homePkgs.vscodium.version} | sort -V | head -n1)" = 1.96.2
  for runtime_script in "${lifecycleSource}" "${supervisorSource}" "${launcherSource}"; do
    ${pkgs.bash}/bin/bash -n "$runtime_script"
    ! ${pkgs.gnugrep}/bin/grep -E \
      '(^|[;|&[:space:]])(awk|flock|readlink|realpath|mkdir|mktemp|mv|rm|ln|rmdir|cp|sed|grep|cut|tr|stat|sleep|date|nix-store|codium|cat|head|tail|wc|pgrep)([;|&[:space:]]|$)' \
      "$runtime_script"
    ! ${pkgs.gnugrep}/bin/grep -q systemd-run "$runtime_script"
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
    # Runtime defaults are store paths. Fakes cross only the external
    # boundaries; the lifecycle, launcher, supervisor, and their filesystem
    # tools must remain runnable when activation supplies no useful PATH.
    export CRIOMOS_VSCODIUM_NIX_STORE="${nixStoreFixture}"
    export CRIOMOS_VSCODIUM_CODIUM="${fakeCodium}"
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
    # The direct launcher retains the same path boundary before it can create
    # a session or hand any descriptor to a child.
    if (cd "$path_guard_cwd" && env CRIOMOS_VSCODIUM_STATE_DIR=relative PATH=/nonexistent "${launcher}"); then false; fi
    test "$(cat "$path_guard_sentinel/content")" = preserved
    test ! -e "$path_guard_cwd/relative"
    # A caller cannot point the supervisor at a foreign session and make its
    # strict nonrecursive cleanup touch it.
    foreign_session="$TMPDIR/foreign/session.ABCDEFGH"
    mkdir -p "$foreign_session"
    printf preserved > "$foreign_session/sentinel"
    if env PATH=/nonexistent "${supervisor}" "$foreign_session" session.ABCDEFGH; then false; fi
    test "$(cat "$foreign_session/sentinel")" = preserved
    rm -rf "$TMPDIR/foreign"
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
    # The standard activation hook must recover a fresh owner state before a
    # GUI process exists: Home Manager already owns the direct stable link,
    # while both lifecycle manifest and mutable discovery registry are absent.
    activation_missing_home="$TMPDIR/activation-missing"
    activation_missing_ext="$activation_missing_home/.vscode-oss/extensions"
    activation_missing_state="$activation_missing_home/state"
    activation_missing_roots="$activation_missing_state/gcroots"
    activation_missing_launch="$TMPDIR/activation-missing-launch"
    mkdir -p "$activation_missing_ext" "$activation_missing_roots" "$activation_missing_launch"
    ln -s ${extDPath} "$activation_missing_ext/anthropic.claude-code"
    ln -s ${extDPath} "$activation_missing_ext/anthropic.claude-code-2.1.220-linux-x64"
    ${pkgs.jq}/bin/jq -n \
      '[{identifier: {id: "anthropic.claude-code"}, version: "2.1.220", relativeLocation: "anthropic.claude-code"},
        {identifier: {id: "openai.chatgpt"}, version: "26.5721.30844", relativeLocation: "openai.chatgpt"}]' \
      > "$activation_missing_ext/.extensions-immutable.json"
    (
      export CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$activation_missing_ext"
      export CRIOMOS_VSCODIUM_STATE_DIR="$activation_missing_state"
      export CRIOMOS_VSCODIUM_GCROOT_DIR="$activation_missing_roots"
      export CRIOMOS_VSCODIUM_LOCK_FILE="$activation_missing_state/lifecycle.lock"
      export FAKE_LAUNCH_DIR="$activation_missing_launch" FAKE_LOCK="$activation_missing_state/lifecycle.lock"
      "${lifecycle}" --activation-refresh
      "${lifecycle}" --activation-refresh
      "${lifecycle}" --activation-refresh
    )
    test "$(head -n1 "$activation_missing_state/manifest")" = v1
    ${pkgs.gnugrep}/bin/grep -Fq $'managed\t2.1.220\tanthropic.claude-code-2.1.220-linux-x64\t' "$activation_missing_state/manifest"
    ${pkgs.jq}/bin/jq -e --arg ext "$activation_missing_ext" \
      '([.[] | select(.identifier.id == "anthropic.claude-code" or .identifier.id == "openai.chatgpt")] | length == 2)
       and any(.[]; .identifier.id == "anthropic.claude-code" and .location.path == ($ext + "/anthropic.claude-code-2.1.220-linux-x64"))
       and any(.[]; .identifier.id == "openai.chatgpt" and .location.path == ($ext + "/openai.chatgpt"))' \
      "$activation_missing_ext/extensions.json" >/dev/null
    test ! -e "$activation_missing_launch/app.started"
    # A previous lifecycle release made versioned links indirect through the
    # stable extension name. After Home Manager moves that name to a new
    # version, the old manifest must remain recognizably owned long enough to
    # install the new link/root and refresh Codium's registry.
    migration_home="$TMPDIR/version-migration"
    migration_ext="$migration_home/.vscode-oss/extensions"
    migration_state="$migration_home/state"
    migration_roots="$migration_state/gcroots"
    migration_launch="$TMPDIR/version-migration-launch"
    mkdir -p "$migration_ext" "$migration_roots" "$migration_launch"
    ln -s ${extAPath} "$migration_ext/anthropic.claude-code"
    ln -s "$migration_ext/anthropic.claude-code" "$migration_ext/anthropic.claude-code-2.1.215-linux-x64"
    ln -s ${extAPath} "$migration_roots/anthropic.claude-code-2.1.215-linux-x64"
    printf 'v1\nmanaged\t2.1.215\tanthropic.claude-code-2.1.215-linux-x64\t%s\n' ${extAPath} > "$migration_state/manifest"
    rm "$migration_ext/anthropic.claude-code"
    ln -s ${extDPath} "$migration_ext/anthropic.claude-code"
    ${pkgs.jq}/bin/jq -n \
      '[{
         identifier: {id: "anthropic.claude-code"},
         version: "2.1.220",
         relativeLocation: "anthropic.claude-code"
       }, {
         identifier: {id: "openai.chatgpt"},
         version: "26.5721.30844",
         relativeLocation: "openai.chatgpt"
       }]' > "$migration_ext/.extensions-immutable.json"
    ${pkgs.jq}/bin/jq -n --arg ext "$migration_ext" \
      '[{
         identifier: {id: "anthropic.claude-code"},
         version: "2.1.215",
         relativeLocation: "anthropic.claude-code-2.1.215-linux-x64",
         location: {path: ($ext + "/anthropic.claude-code-2.1.215-linux-x64")}
       }, {
         identifier: {id: "openai.chatgpt"},
         version: "26.5602.71036",
         relativeLocation: "openai.chatgpt",
         location: {path: ($ext + "/openai.chatgpt")}
       }, {
         identifier: {id: "fixture.unmanaged"},
         version: "7.4.2",
         relativeLocation: "fixture.unmanaged",
         location: {path: ($ext + "/fixture.unmanaged"), fsPath: ($ext + "/fixture.unmanaged")},
         metadata: {preserve: true, nested: ["one", "two"]}
       }]' > "$migration_ext/extensions.json"
    ${pkgs.jq}/bin/jq -S \
      '[.[] | select(.identifier.id != "anthropic.claude-code" and .identifier.id != "openai.chatgpt")]' \
      "$migration_ext/extensions.json" > "$migration_launch/unmanaged-before.json"
    export FAKE_LAUNCH_DIR="$migration_launch" FAKE_LOCK="$migration_state/lifecycle.lock"
    env \
      CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$migration_ext" \
      CRIOMOS_VSCODIUM_STATE_DIR="$migration_state" \
      CRIOMOS_VSCODIUM_GCROOT_DIR="$migration_roots" \
      CRIOMOS_VSCODIUM_LOCK_FILE="$migration_state/lifecycle.lock" \
      "${lifecycle}" --activation-refresh
    env \
      CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$migration_ext" \
      CRIOMOS_VSCODIUM_STATE_DIR="$migration_state" \
      CRIOMOS_VSCODIUM_GCROOT_DIR="$migration_roots" \
      CRIOMOS_VSCODIUM_LOCK_FILE="$migration_state/lifecycle.lock" \
      "${lifecycle}" --prepare-launch
    test -L "$migration_ext/anthropic.claude-code-2.1.220-linux-x64"
    test "$(readlink -f "$migration_ext/anthropic.claude-code-2.1.220-linux-x64")" = "$(readlink -f ${extDPath})"
    test -L "$migration_roots/anthropic.claude-code-2.1.220-linux-x64"
    test "$(readlink -f "$migration_roots/anthropic.claude-code-2.1.220-linux-x64")" = "$(readlink -f ${extD})"
    test ! -e "$migration_ext/anthropic.claude-code-2.1.215-linux-x64"
    test ! -e "$migration_roots/anthropic.claude-code-2.1.215-linux-x64"
    test "$(head -n1 "$migration_state/manifest")" = v1
    ${pkgs.gnugrep}/bin/grep -Fq $'managed\t2.1.220\tanthropic.claude-code-2.1.220-linux-x64\t' "$migration_state/manifest"
    ! ${pkgs.gnugrep}/bin/grep -q 2.1.215 "$migration_state/manifest"
    ${pkgs.jq}/bin/jq -e --arg ext "$migration_ext" \
      'any(.[];
          .identifier.id == "anthropic.claude-code"
          and .version == "2.1.220"
          and .relativeLocation == "anthropic.claude-code-2.1.220-linux-x64"
          and .location.path == ($ext + "/anthropic.claude-code-2.1.220-linux-x64")
          and .location.fsPath == ($ext + "/anthropic.claude-code-2.1.220-linux-x64")
        )
       and any(.[];
          .identifier.id == "openai.chatgpt"
          and .version == "26.5721.30844"
          and .relativeLocation == "openai.chatgpt"
          and .location.path == ($ext + "/openai.chatgpt")
          and .location.fsPath == ($ext + "/openai.chatgpt")
        )' \
      "$migration_ext/extensions.json"
    ${pkgs.jq}/bin/jq -S \
      '[.[] | select(.identifier.id != "anthropic.claude-code" and .identifier.id != "openai.chatgpt")]' \
      "$migration_ext/extensions.json" > "$migration_launch/unmanaged-after.json"
    cmp "$migration_launch/unmanaged-before.json" "$migration_launch/unmanaged-after.json"
    cmp "$migration_ext/.extensions-immutable.json" "$migration_state/extensions-immutable.registry.json"
    test ! -e "$migration_launch/refresh-gap"
    test ! -e "$migration_launch/codium.pid"
    # A direct old v1 entry can safely repair a missing root, then migrate to
    # the newer direct link before activation refreshes the immutable registry.
    missing_root_home="$TMPDIR/missing-root-migration"
    missing_root_ext="$missing_root_home/.vscode-oss/extensions"
    missing_root_state="$missing_root_home/state"
    missing_root_roots="$missing_root_state/gcroots"
    missing_root_launch="$TMPDIR/missing-root-migration-launch"
    mkdir -p "$missing_root_ext" "$missing_root_roots" "$missing_root_launch"
    ln -s ${extAPath} "$missing_root_ext/anthropic.claude-code"
    ln -s ${extAPath} "$missing_root_ext/anthropic.claude-code-2.1.215-linux-x64"
    printf 'v1\nmanaged\t2.1.215\tanthropic.claude-code-2.1.215-linux-x64\t%s\n' ${extAPath} > "$missing_root_state/manifest"
    rm "$missing_root_ext/anthropic.claude-code"
    ln -s ${extDPath} "$missing_root_ext/anthropic.claude-code"
    cp "$migration_ext/.extensions-immutable.json" "$missing_root_ext/.extensions-immutable.json"
    printf '%s\n' "[{\"identifier\":{\"id\":\"anthropic.claude-code\"},\"version\":\"2.1.215\",\"relativeLocation\":\"anthropic.claude-code-2.1.215-linux-x64\",\"location\":{\"path\":\"$missing_root_ext/anthropic.claude-code-2.1.215-linux-x64\"}},{\"identifier\":{\"id\":\"openai.chatgpt\"},\"version\":\"26.5602.71036\",\"relativeLocation\":\"openai.chatgpt\",\"location\":{\"path\":\"$missing_root_ext/openai.chatgpt\"}}]" > "$missing_root_ext/extensions.json"
    export FAKE_LAUNCH_DIR="$missing_root_launch" FAKE_LOCK="$missing_root_state/lifecycle.lock"
    env \
      CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$missing_root_ext" \
      CRIOMOS_VSCODIUM_STATE_DIR="$missing_root_state" \
      CRIOMOS_VSCODIUM_GCROOT_DIR="$missing_root_roots" \
      CRIOMOS_VSCODIUM_LOCK_FILE="$missing_root_state/lifecycle.lock" \
      "${lifecycle}" --activation-refresh
    test -L "$missing_root_ext/anthropic.claude-code-2.1.220-linux-x64"
    test "$(readlink -f "$missing_root_ext/anthropic.claude-code-2.1.220-linux-x64")" = "$(readlink -f ${extDPath})"
    test -L "$missing_root_roots/anthropic.claude-code-2.1.220-linux-x64"
    test "$(readlink -f "$missing_root_roots/anthropic.claude-code-2.1.220-linux-x64")" = "$(readlink -f ${extD})"
    test ! -e "$missing_root_ext/anthropic.claude-code-2.1.215-linux-x64"
    test ! -e "$missing_root_roots/anthropic.claude-code-2.1.215-linux-x64"
    test "$(head -n1 "$missing_root_state/manifest")" = v1
    ! ${pkgs.gnugrep}/bin/grep -q 2.1.215 "$missing_root_state/manifest"
    ${pkgs.jq}/bin/jq -e \
      'any(.[]; .identifier.id == "anthropic.claude-code" and .version == "2.1.220" and .relativeLocation == "anthropic.claude-code-2.1.220-linux-x64")
       and any(.[]; .identifier.id == "openai.chatgpt" and .version == "26.5721.30844")' \
      "$missing_root_ext/extensions.json"
    cmp "$missing_root_ext/.extensions-immutable.json" "$missing_root_state/extensions-immutable.registry.json"
    test ! -e "$missing_root_launch/refresh-gap"
    test ! -e "$missing_root_launch/codium.pid"
    write_recovery_immutable() {
      recovery_ext="$1"
      ln -s ${immutableCurrent} "$recovery_ext/.extensions-immutable.json"
    }
    write_stale_recovery_registry() {
      recovery_ext="$1"
      ${pkgs.jq}/bin/jq -n --arg ext "$recovery_ext" \
        '[{
           identifier: {id: "anthropic.claude-code"},
           version: "${transitionPreviousVersion}",
           relativeLocation: "anthropic.claude-code-${transitionPreviousVersion}-linux-x64",
           location: {
             path: ($ext + "/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"),
             fsPath: ($ext + "/anthropic.claude-code-${transitionPreviousVersion}-linux-x64")
           }
         }, {
           identifier: {id: "openai.chatgpt"},
           version: "${transitionPreviousOpenaiVersion}",
           relativeLocation: "openai.chatgpt",
           location: {path: ($ext + "/openai.chatgpt"), fsPath: ($ext + "/openai.chatgpt")}
         }, {
           identifier: {id: "fixture.unmanaged"},
           version: "9.8.7",
           relativeLocation: "fixture.unmanaged",
           location: {path: ($ext + "/fixture.unmanaged"), fsPath: ($ext + "/fixture.unmanaged")},
           metadata: {preserve: true, nested: ["alpha", "beta"]}
         }]' > "$recovery_ext/extensions.json"
    }
    capture_recovery_state() {
      recovery_ext="$1" recovery_state="$2" recovery_roots="$3" recovery_output="$4"
      {
        find -P "$recovery_ext" "$recovery_roots" -printf '%p %y %l\n' | sort
        for recovery_file in \
          "$recovery_state/manifest" \
          "$recovery_ext/.extensions-immutable.json" \
          "$recovery_ext/extensions.json" \
          "$recovery_state/extensions-immutable.registry.json"; do
          printf 'FILE %s\n' "$recovery_file"
          if [ -f "$recovery_file" ]; then cat "$recovery_file"; else printf 'ABSENT\n'; fi
        done
      } > "$recovery_output"
    }
    setup_failed_recovery() {
      failure_label="$1"
      failure_home="$TMPDIR/$failure_label"
      failure_ext="$failure_home/.vscode-oss/extensions"
      failure_state="$failure_home/state"
      failure_roots="$failure_state/gcroots"
      failure_launch="$TMPDIR/$failure_label-launch"
      mkdir -p "$failure_ext" "$failure_roots" "$failure_launch"
      ln -s ${transitionCurrentExtPath} "$failure_ext/anthropic.claude-code"
      write_recovery_immutable "$failure_ext"
      write_stale_recovery_registry "$failure_ext"
      printf '%s\n' '[{"stale-owner-state":true}]' > "$failure_state/extensions-immutable.registry.json"
    }
    assert_failed_managed_launch() {
      if env \
        CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$failure_ext" \
        CRIOMOS_VSCODIUM_STATE_DIR="$failure_state" \
        CRIOMOS_VSCODIUM_GCROOT_DIR="$failure_roots" \
        CRIOMOS_VSCODIUM_LOCK_FILE="$failure_state/lifecycle.lock" \
        FAKE_LAUNCH_DIR="$failure_launch" \
        FAKE_LOCK="$failure_state/lifecycle.lock" \
        "${launcher}" 2> "$failure_launch/stderr"; then
        false
      fi
      ${pkgs.gnugrep}/bin/grep -Fq \
        'Managed extension state is inconsistent. Contact the system steward; no extension collision was overwritten.' \
        "$failure_launch/stderr"
      test "$(wc -l < "$failure_launch/notifier.calls")" -eq 1
      ${pkgs.gnugrep}/bin/grep -Fq 'VSCodium could not start' "$failure_launch/notifier.calls"
      ${pkgs.gnugrep}/bin/grep -Fq 'no extension collision was overwritten' "$failure_launch/notifier.calls"
      test ! -e "$failure_launch/app.started"
      test ! -e "$failure_launch/app.launches"
      test ! -e "$failure_launch/codium.pid"
      test ! -e "$failure_launch/supervisor.pid"
    }

    # A prior managed version can retain its exact root after its versioned
    # link disappears while Home Manager declares a newer immutable version.
    # The launcher authenticates and restores that link, migrates to the
    # current tuple, preserves the other managed extension and an unrelated
    # registry row, and starts the application exactly once.
    retained_home="$TMPDIR/retained-version-transition"
    retained_ext="$retained_home/.vscode-oss/extensions"
    retained_state="$retained_home/state"
    retained_roots="$retained_state/gcroots"
    retained_launch="$TMPDIR/retained-version-transition-launch"
    mkdir -p "$retained_ext" "$retained_roots" "$retained_launch"
    ln -s ${transitionCurrentExtPath} "$retained_ext/anthropic.claude-code"
    ln -s "$retained_ext/anthropic.claude-code" \
      "$retained_ext/anthropic.claude-code-${transitionLegacyAliasVersion}-linux-x64"
    ln -s ${transitionOpenaiExtPath} "$retained_ext/openai.chatgpt"
    ln -s ${transitionOpenaiExtPath} \
      "$retained_ext/openai.chatgpt-${transitionOpenaiVersion}-linux-x64"
    ln -s ${transitionPreviousExt} \
      "$retained_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${transitionPreviousExtPath} > "$retained_state/manifest"
    write_recovery_immutable "$retained_ext"
    write_stale_recovery_registry "$retained_ext"
    ${pkgs.jq}/bin/jq -S \
      '[.[] | select(.identifier.id != "anthropic.claude-code" and .identifier.id != "openai.chatgpt")]' \
      "$retained_ext/extensions.json" > "$retained_launch/unmanaged-before.json"
    caller_cgroup="$(<"/proc/$$/cgroup")"
    env \
      CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$retained_ext" \
      CRIOMOS_VSCODIUM_STATE_DIR="$retained_state" \
      CRIOMOS_VSCODIUM_GCROOT_DIR="$retained_roots" \
      CRIOMOS_VSCODIUM_LOCK_FILE="$retained_state/lifecycle.lock" \
      FAKE_LAUNCH_DIR="$retained_launch" \
      FAKE_LOCK="$retained_state/lifecycle.lock" \
      FAKE_CALLER_CGROUP="$caller_cgroup" \
      FAKE_CODIUM_CLOSE_FD9=1 \
      FAKE_CODIUM_SCAN_FILESYSTEM=1 \
      FAKE_APP_SECONDS=0.2 \
      "${launcher}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      [ -e "$retained_launch/app.started" ] && break
      sleep 0.1
    done
    test "$(wc -l < "$retained_launch/app.launches")" -eq 1
    test -e "$retained_launch/app.started"
    test ! -e "$retained_launch/notifier.calls"
    test -L "$retained_ext/anthropic.claude-code-${transitionCurrentVersion}-linux-x64"
    test "$(readlink -f "$retained_ext/anthropic.claude-code-${transitionCurrentVersion}-linux-x64")" = \
      "$(readlink -f ${transitionCurrentExtPath})"
    test -L "$retained_roots/anthropic.claude-code-${transitionCurrentVersion}-linux-x64"
    test "$(readlink -f "$retained_roots/anthropic.claude-code-${transitionCurrentVersion}-linux-x64")" = \
      "$(readlink -f ${transitionCurrentExt})"
    test ! -e "$retained_ext/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    test ! -e "$retained_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    test -L "$retained_ext/anthropic.claude-code-${transitionLegacyAliasVersion}-linux-x64"
    test "$(readlink "$retained_ext/anthropic.claude-code-${transitionLegacyAliasVersion}-linux-x64")" = \
      "$retained_ext/anthropic.claude-code"
    test "$(readlink -f "$retained_ext/anthropic.claude-code-${transitionLegacyAliasVersion}-linux-x64")" = \
      "$(readlink -f ${transitionCurrentExtPath})"
    test -L "$retained_ext/openai.chatgpt"
    test -L "$retained_ext/openai.chatgpt-${transitionOpenaiVersion}-linux-x64"
    test "$(wc -l < "$retained_state/manifest")" -eq 2
    test "$(head -n1 "$retained_state/manifest")" = v1
    ${pkgs.gnugrep}/bin/grep -Fq \
      $'managed\t${transitionCurrentVersion}\tanthropic.claude-code-${transitionCurrentVersion}-linux-x64\t' \
      "$retained_state/manifest"
    ${pkgs.jq}/bin/jq -e --arg ext "$retained_ext" \
      'any(.[]; .identifier.id == "anthropic.claude-code"
          and .version == "${transitionCurrentVersion}"
          and .relativeLocation == "anthropic.claude-code-${transitionCurrentVersion}-linux-x64"
          and .location.path == ($ext + "/anthropic.claude-code-${transitionCurrentVersion}-linux-x64")
          and .location.fsPath == ($ext + "/anthropic.claude-code-${transitionCurrentVersion}-linux-x64"))
       and any(.[]; .identifier.id == "openai.chatgpt"
          and .version == "${transitionOpenaiVersion}"
          and .relativeLocation == "openai.chatgpt"
          and .location.path == ($ext + "/openai.chatgpt")
          and .location.fsPath == ($ext + "/openai.chatgpt"))' \
      "$retained_ext/extensions.json"
    ${pkgs.jq}/bin/jq -S \
      '[.[] | select(.identifier.id != "anthropic.claude-code" and .identifier.id != "openai.chatgpt")]' \
      "$retained_ext/extensions.json" > "$retained_launch/unmanaged-after.json"
    cmp "$retained_launch/unmanaged-before.json" "$retained_launch/unmanaged-after.json"
    cmp "$retained_ext/.extensions-immutable.json" "$retained_state/extensions-immutable.registry.json"
    ${pkgs.gnugrep}/bin/grep -Fq \
      'claude anthropic.claude-code-${transitionLegacyAliasVersion}-linux-x64 ' \
      "$retained_launch/refresh-discovery"
    ${pkgs.gnugrep}/bin/grep -Fq \
      'claude anthropic.claude-code-${transitionCurrentVersion}-linux-x64 ' \
      "$retained_launch/refresh-discovery"
    ${pkgs.gnugrep}/bin/grep -Fq 'openai openai.chatgpt ' "$retained_launch/refresh-discovery"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      ${pkgs.util-linux}/bin/flock -xn "$retained_state/lifecycle.lock" true && break
      sleep 0.1
    done
    ${pkgs.util-linux}/bin/flock -xn "$retained_state/lifecycle.lock" true
    test "$(wc -l < "$retained_launch/app.launches")" -eq 1

    # Existing filesystem collisions are never replaced by missing-link
    # recovery. The managed launcher surfaces the failure and does not reach
    # either the supervisor or mutable registry refresh.
    setup_failed_recovery retained-link-directory-collision
    ln -s ${transitionPreviousExt} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    mkdir "$failure_ext/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    printf preserved > \
      "$failure_ext/anthropic.claude-code-${transitionPreviousVersion}-linux-x64/sentinel"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${transitionPreviousExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"
    test "$(cat "$failure_ext/anthropic.claude-code-${transitionPreviousVersion}-linux-x64/sentinel")" = preserved

    # A different extension output is foreign at the retained root boundary,
    # even though the root filename looks owned.
    setup_failed_recovery retained-wrong-root
    ln -s ${extA} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${transitionPreviousExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"

    # Matching semver is insufficient authority: publisher and extension name
    # must identify the retained target as Anthropic's Claude extension.
    setup_failed_recovery retained-adversarial-package
    ln -s ${adversarialExt} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${adversarialExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"

    # Immutable authority is the Home Manager store symlink, not merely JSON
    # with the right bytes. Regular user state and a foreign symlink cannot
    # authorize recreating a missing lifecycle link.
    setup_failed_recovery retained-regular-immutable
    ln -s ${transitionPreviousExt} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    rm "$failure_ext/.extensions-immutable.json"
    cp ${immutableCurrent} "$failure_ext/.extensions-immutable.json"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${transitionPreviousExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"

    setup_failed_recovery retained-foreign-immutable
    ln -s ${transitionPreviousExt} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    rm "$failure_ext/.extensions-immutable.json"
    cp ${immutableCurrent} "$failure_home/foreign-immutable.json"
    ln -s "$failure_home/foreign-immutable.json" "$failure_ext/.extensions-immutable.json"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\n' \
      ${transitionPreviousExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"

    # No repair discovered in an early row may execute before the complete
    # manifest is accepted. A malformed later row preserves the full state.
    setup_failed_recovery later-malformed-row
    ln -s ${transitionPreviousExt} \
      "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    printf 'v1\nmanaged\t${transitionPreviousVersion}\tanthropic.claude-code-${transitionPreviousVersion}-linux-x64\t%s\nmalformed-row\n' \
      ${transitionPreviousExtPath} > "$failure_state/manifest"
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/before"
    assert_failed_managed_launch
    capture_recovery_state "$failure_ext" "$failure_state" "$failure_roots" "$failure_launch/after"
    cmp "$failure_launch/before" "$failure_launch/after"
    test ! -e \
      "$failure_ext/anthropic.claude-code-${transitionPreviousVersion}-linux-x64"
    test "$(readlink -f "$failure_roots/anthropic.claude-code-${transitionPreviousVersion}-linux-x64")" = \
      "$(readlink -f ${transitionPreviousExt})"

    # Regression: a previously managed automatic root already named for the
    # Home-declared 2.1.223 extension can still resolve to 2.1.220. The exact
    # manifest entry, direct current link, and old extension output authorize
    # an atomic replacement; activation then reaches registry readiness
    # without starting a Codium GUI process.
    wrong_root_home="$TMPDIR/wrong-root"
    wrong_root_ext="$wrong_root_home/.vscode-oss/extensions"
    wrong_root_state="$wrong_root_home/state"
    wrong_root_roots="$wrong_root_state/gcroots"
    wrong_root_launch="$TMPDIR/wrong-root-launch"
    mkdir -p "$wrong_root_ext" "$wrong_root_roots" "$wrong_root_launch"
    ln -s ${extEPath} "$wrong_root_ext/anthropic.claude-code"
    ln -s ${extEPath} "$wrong_root_ext/anthropic.claude-code-2.1.223-linux-x64"
    ln -s ${extD} "$wrong_root_roots/anthropic.claude-code-2.1.223-linux-x64"
    printf 'v1\nmanaged\t2.1.223\tanthropic.claude-code-2.1.223-linux-x64\t%s\n' ${extEPath} > "$wrong_root_state/manifest"
    ${pkgs.jq}/bin/jq -n \
      '[{identifier: {id: "anthropic.claude-code"}, version: "2.1.223", relativeLocation: "anthropic.claude-code"},
        {identifier: {id: "openai.chatgpt"}, version: "26.5721.30844", relativeLocation: "openai.chatgpt"}]' \
      > "$wrong_root_ext/.extensions-immutable.json"
    printf '%s\n' "[{\"identifier\":{\"id\":\"anthropic.claude-code\"},\"version\":\"2.1.220\",\"relativeLocation\":\"anthropic.claude-code-2.1.220-linux-x64\",\"location\":{\"path\":\"$wrong_root_ext/anthropic.claude-code-2.1.220-linux-x64\"}},{\"identifier\":{\"id\":\"openai.chatgpt\"},\"version\":\"26.5602.71036\",\"relativeLocation\":\"openai.chatgpt\",\"location\":{\"path\":\"$wrong_root_ext/openai.chatgpt\"}}]" > "$wrong_root_ext/extensions.json"
    export FAKE_LAUNCH_DIR="$wrong_root_launch" FAKE_LOCK="$wrong_root_state/lifecycle.lock"
    env \
      CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$wrong_root_ext" \
      CRIOMOS_VSCODIUM_STATE_DIR="$wrong_root_state" \
      CRIOMOS_VSCODIUM_GCROOT_DIR="$wrong_root_roots" \
      CRIOMOS_VSCODIUM_LOCK_FILE="$wrong_root_state/lifecycle.lock" \
      "${lifecycle}" --activation-refresh
    test -L "$wrong_root_roots/anthropic.claude-code-2.1.223-linux-x64"
    test "$(readlink -f "$wrong_root_roots/anthropic.claude-code-2.1.223-linux-x64")" = "$(readlink -f ${extE})"
    ${pkgs.gnugrep}/bin/grep -Fq $'managed\t2.1.223\tanthropic.claude-code-2.1.223-linux-x64\t' "$wrong_root_state/manifest"
    ${pkgs.jq}/bin/jq -e --arg ext "$wrong_root_ext" \
      'any(.[]; .identifier.id == "anthropic.claude-code"
          and .version == "2.1.223"
          and .relativeLocation == "anthropic.claude-code-2.1.223-linux-x64"
          and .location.path == ($ext + "/anthropic.claude-code-2.1.223-linux-x64"))' \
      "$wrong_root_ext/extensions.json"
    cmp "$wrong_root_ext/.extensions-immutable.json" "$wrong_root_state/extensions-immutable.registry.json"
    test ! -e "$wrong_root_launch/refresh-gap"
    test ! -e "$wrong_root_launch/codium.pid"
    # A failed replacement restores the old owned stale root exactly and does
    # not make the registry ready.
    failed_root_home="$TMPDIR/failed-root"
    failed_root_ext="$failed_root_home/.vscode-oss/extensions"
    failed_root_state="$failed_root_home/state"
    failed_root_roots="$failed_root_state/gcroots"
    mkdir -p "$failed_root_ext" "$failed_root_roots"
    ln -s ${extEPath} "$failed_root_ext/anthropic.claude-code"
    ln -s ${extEPath} "$failed_root_ext/anthropic.claude-code-2.1.223-linux-x64"
    ln -s ${extD} "$failed_root_roots/anthropic.claude-code-2.1.223-linux-x64"
    printf 'v1\nmanaged\t2.1.223\tanthropic.claude-code-2.1.223-linux-x64\t%s\n' ${extEPath} > "$failed_root_state/manifest"
    cp "$wrong_root_ext/.extensions-immutable.json" "$failed_root_ext/.extensions-immutable.json"
    cp "$wrong_root_ext/extensions.json" "$failed_root_ext/extensions.json"
    cp "$failed_root_ext/extensions.json" "$TMPDIR/failed-root.registry.before"
    env CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$failed_root_ext" CRIOMOS_VSCODIUM_STATE_DIR="$failed_root_state" CRIOMOS_VSCODIUM_GCROOT_DIR="$failed_root_roots" CRIOMOS_VSCODIUM_LOCK_FILE="$failed_root_state/lifecycle.lock" CRIOMOS_VSCODIUM_NIX_STORE=${pkgs.coreutils}/bin/false "${lifecycle}" --activation-refresh
    test "$(readlink -f "$failed_root_roots/anthropic.claude-code-2.1.223-linux-x64")" = "$(readlink -f ${extD})"
    ! find "$failed_root_roots" -maxdepth 1 -name 'anthropic.claude-code-2.1.223-linux-x64.stale.*' | grep -q .
    cmp "$TMPDIR/failed-root.registry.before" "$failed_root_ext/extensions.json"
    test ! -e "$failed_root_state/extensions-immutable.registry.json"
    # A generic store output at the managed name is not a stale Claude root;
    # preserve it and do not let activation reach registry convergence.
    foreign_root_home="$TMPDIR/foreign-root"
    foreign_root_ext="$foreign_root_home/.vscode-oss/extensions"
    foreign_root_state="$foreign_root_home/state"
    foreign_root_roots="$foreign_root_state/gcroots"
    mkdir -p "$foreign_root_ext" "$foreign_root_roots"
    ln -s ${extEPath} "$foreign_root_ext/anthropic.claude-code"
    ln -s ${extEPath} "$foreign_root_ext/anthropic.claude-code-2.1.223-linux-x64"
    ln -s ${foreignRoot} "$foreign_root_roots/anthropic.claude-code-2.1.223-linux-x64"
    printf 'v1\nmanaged\t2.1.223\tanthropic.claude-code-2.1.223-linux-x64\t%s\n' ${extEPath} > "$foreign_root_state/manifest"
    cp "$wrong_root_ext/.extensions-immutable.json" "$foreign_root_ext/.extensions-immutable.json"
    cp "$wrong_root_ext/extensions.json" "$foreign_root_ext/extensions.json"
    { find -P "$foreign_root_ext" "$foreign_root_roots" -printf '%p %y %l\n' | sort; cat "$foreign_root_state/manifest"; cat "$foreign_root_ext/extensions.json"; } > "$TMPDIR/foreign-root.before"
    env CRIOMOS_VSCODIUM_EXTENSIONS_DIR="$foreign_root_ext" CRIOMOS_VSCODIUM_STATE_DIR="$foreign_root_state" CRIOMOS_VSCODIUM_GCROOT_DIR="$foreign_root_roots" CRIOMOS_VSCODIUM_LOCK_FILE="$foreign_root_state/lifecycle.lock" "${lifecycle}" --activation-refresh
    { find -P "$foreign_root_ext" "$foreign_root_roots" -printf '%p %y %l\n' | sort; cat "$foreign_root_state/manifest"; cat "$foreign_root_ext/extensions.json"; } > "$TMPDIR/foreign-root.after"
    cmp "$TMPDIR/foreign-root.before" "$TMPDIR/foreign-root.after"
    test "$(cat ${foreignRoot}/sentinel)" = foreign
    test ! -e "$foreign_root_state/extensions-immutable.registry.json"
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
    # mutable registry has a stale same-version location. Launch refreshes via
    # the supported underlying CLI, then hands its SH lease to a same-cgroup
    # direct supervisor. A forbidden runtime command detects any regression.
    launch_dir="$TMPDIR/direct-launch"
    mkdir -p "$launch_dir"
    export FAKE_LAUNCH_DIR="$launch_dir" FAKE_LOCK="$state/lifecycle.lock" FAKE_APP_SECONDS=5
    forbidden_systemd_run="$launch_dir/forbidden-systemd-run"
    printf '#!%s\ntouch %s\nexit 97\n' "${pkgs.runtimeShell}" "$launch_dir/systemd-run.called" > "$forbidden_systemd_run"
    chmod +x "$forbidden_systemd_run"
    export CRIOMOS_VSCODIUM_SYSTEMD_RUN="$forbidden_systemd_run"
    immutable="$ext/.extensions-immutable.json"
    ${pkgs.jq}/bin/jq -n \
      '[{
         identifier: {id: "anthropic.claude-code"},
         version: "2.1.215",
         relativeLocation: "anthropic.claude-code"
       }, {
         identifier: {id: "openai.chatgpt"},
         version: "26.5721.30844",
         relativeLocation: "openai.chatgpt"
       }]' > "$immutable"
    cp "$immutable" "$TMPDIR/immutable.before"
    printf '%s\n' "[{\"identifier\":{\"id\":\"anthropic.claude-code\"},\"version\":\"2.1.198\",\"relativeLocation\":\"anthropic.claude-code-2.1.198-linux-x64\",\"location\":{\"path\":\"$ext/anthropic.claude-code-2.1.198-linux-x64\"}},{\"identifier\":{\"id\":\"openai.chatgpt\"},\"version\":\"26.5422.30944\",\"relativeLocation\":\"openai.chatgpt\",\"location\":{\"path\":\"$ext/openai.chatgpt\"}},{\"identifier\":{\"id\":\"unmanaged.fixture\"},\"location\":{\"path\":\"$ext/unmanaged.fixture\"}}]" > "$ext/extensions.json"
    "${lifecycle}" --activation-refresh
    test ! -e "$launch_dir/refresh-gap"
    ${pkgs.jq}/bin/jq -e --arg path "$ext/anthropic.claude-code-2.1.215-linux-x64" \
      'any(.[]; .identifier.id == "anthropic.claude-code" and .location.path == $path)' "$ext/extensions.json"
    ${pkgs.jq}/bin/jq -e \
      'any(.[]; .identifier.id == "openai.chatgpt" and .version == "26.5721.30844")' \
      "$ext/extensions.json"
    ${pkgs.jq}/bin/jq 'map(if .identifier.id == "anthropic.claude-code" then .location.path = "'$ext'/anthropic.claude-code-2.1.198-linux-x64" else . end)' \
      "$ext/extensions.json" > "$ext/extensions.json.tmp"
    mv "$ext/extensions.json.tmp" "$ext/extensions.json"
    unmanaged_before=$(${pkgs.jq}/bin/jq -c '[.[] | select(.identifier.id == "unmanaged.fixture")]' "$ext/extensions.json" | sha256sum)
    caller_cgroup="$(<"/proc/$$/cgroup")"
    env PATH=/nonexistent FAKE_CALLER_CGROUP="$caller_cgroup" FAKE_CODIUM_CLOSE_FD9=1 "${launcher}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$launch_dir/app.started" ] && break; sleep 0.1; done
    test -e "$launch_dir/app.started"
    test ! -e "$launch_dir/systemd-run.called"
    # The Codium fixture closes inherited FD 9. Its parent supervisor still
    # owns SH, so an exclusive activation must defer after the launcher exits.
    ! ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    "${lifecycle}" --activation-refresh
    ! ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    cmp "$TMPDIR/immutable.before" "$immutable"
    ${pkgs.jq}/bin/jq -e --arg path "$ext/anthropic.claude-code-2.1.215-linux-x64" \
      'any(.[]; .identifier.id == "anthropic.claude-code" and .location.path == $path)' "$ext/extensions.json"
    unmanaged_after=$(${pkgs.jq}/bin/jq -c '[.[] | select(.identifier.id == "unmanaged.fixture")]' "$ext/extensions.json" | sha256sum)
    test "$unmanaged_before" = "$unmanaged_after"
    ${pkgs.jq}/bin/jq \
      'map(if .identifier.id == "openai.chatgpt" then .version = "26.6000.0" else . end)' \
      "$immutable" > "$immutable.tmp"
    mv "$immutable.tmp" "$immutable"
    cp "$immutable" "$TMPDIR/immutable.deferred"
    "${lifecycle}" --activation-refresh
    ! ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    cmp "$TMPDIR/immutable.deferred" "$immutable"
    ${pkgs.jq}/bin/jq -e \
      'any(.[]; .identifier.id == "openai.chatgpt" and .version == "26.5721.30844")' \
      "$ext/extensions.json"
    codium_pid=$(cat "$launch_dir/codium.pid")
    supervisor_pid=$(cat "$launch_dir/supervisor.pid")
    child_a=$(sed -n '1p' "$launch_dir/children")
    child_b=$(sed -n '2p' "$launch_dir/children")
    # Interrupting the supervisor targets only its exact foreground Codium
    # child. The fixture's Codium trap reaps its own children, so no child,
    # supervisor, session, or SH lease can outlive the interrupted launch.
    kill -TERM "$supervisor_pid"
    for _ in 1 2 3 4 5 6 7 8 9 10; do ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true && break; sleep 0.1; done
    ${pkgs.util-linux}/bin/flock -xn "$state/lifecycle.lock" true
    ! kill -0 "$codium_pid" 2>/dev/null
    ! kill -0 "$supervisor_pid" 2>/dev/null
    ! kill -0 "$child_a" 2>/dev/null
    ! kill -0 "$child_b" 2>/dev/null
    ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q .
    "${lifecycle}" --prepare-launch
    ${pkgs.jq}/bin/jq -e \
      'any(.[]; .identifier.id == "openai.chatgpt" and .version == "26.6000.0")' \
      "$ext/extensions.json"
    cmp "$immutable" "$state/extensions-immutable.registry.json"
    # A CLI-like Codium command may exit before the launcher's next probe. The
    # authenticated started/ready/status handshake must return promptly and
    # reclaim its one-shot session state without a false timeout.
    rm -f "$launch_dir/version.called"
    cli_started=$(${pkgs.coreutils}/bin/date +%s%N)
    cli_output="$("${launcher}" --version)"
    cli_elapsed=$(($(${pkgs.coreutils}/bin/date +%s%N) - cli_started))
    test "$cli_elapsed" -lt 1000000000
    test "$cli_output" = fixture-version
    test -e "$launch_dir/version.called"
    for _ in 1 2 3 4 5 6 7 8 9 10; do ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q . && break; sleep 0.1; done
    ! find "$state" -maxdepth 1 -type d -name 'session.*' | grep -q .
    set +e
    cli_output=$(FAKE_CODIUM_CLI_OUTPUT=fixture-status-failure FAKE_CODIUM_CLI_STATUS=37 "${launcher}" --status)
    cli_status=$?
    set -e
    test "$cli_status" -eq 37
    test "$cli_output" = fixture-status-failure
    # A failed supported refresh restores the original registry and no GUI
    # session survives: launch is fail-closed rather than running with drift.
    cp "$ext/extensions.json" "$TMPDIR/registry.before-failure"
    ${pkgs.jq}/bin/jq 'map(if .identifier.id == "anthropic.claude-code" then .location.path = "'$ext'/anthropic.claude-code-2.1.198-linux-x64" else . end)' \
      "$ext/extensions.json" > "$ext/extensions.json.tmp"
    mv "$ext/extensions.json.tmp" "$ext/extensions.json"
    cp "$ext/extensions.json" "$TMPDIR/registry.stale-before-failure"
    rm -f "$launch_dir/app.started"
    if FAKE_CODIUM_FAIL=1 "${launcher}"; then false; fi
    cmp "$TMPDIR/registry.stale-before-failure" "$ext/extensions.json"
    test ! -e "$launch_dir/app.started"
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
