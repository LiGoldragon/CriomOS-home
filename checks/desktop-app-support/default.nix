{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (lib.composeManyExtensions (import ../../overlays { inherit inputs; }));
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix {
    pkgs = homePkgs;
    inherit inputs;
    chatgptCommandLineArgs = "--ozone-platform=wayland";
  };
  sourceData = builtins.fromJSON (builtins.readFile ../../owned-agents/chatgpt/hashes.json);
  source = sourceData.sources.${system} or (throw "Unsupported ChatGPT platform: ${system}");
  pristineArchive = pkgs.fetchurl {
    inherit (source) url hash;
  };
  chatgptPackage = ownedAgentPackages.chatgptPackage;
  chatgptUnwrapped = chatgptPackage.passthru.unwrapped;
  chatgptCompanion = "${chatgptUnwrapped}/lib/chatgpt/resources/codex";
  chatgptGeneratedBytecodeDirectory = ../../owned-agents/chatgpt/__pycache__;
  chatgptWrapperProbeUnwrapped = pkgs.runCommand "chatgpt-wrapper-probe-unwrapped" {
    passthru.version = source.version;
  } ''
    mkdir -p "$out/bin" "$out/share"
    cat > "$out/bin/chatgpt" <<'EOF'
    #!${pkgs.runtimeShell}
    printf '%s|%s|%s|%s|%s|%s\n' \
      "''${CODEX_APP_SERVER_USE_LOCAL_DAEMON-}" \
      "''${CODEX_CLI_PATH-}" \
      "''${CODEX_APP_SERVER_FORCE_CLI-}" \
      "''${CODEX_APP_SERVER_CLI_COMMAND-}" \
      "''${CODEX_APP_TOOLS_PIPE_PATH-}" \
      "$*" > "$CHATGPT_WRAPPER_PROBE_OUT"
    EOF
    chmod +x "$out/bin/chatgpt"
  '';
  chatgptWrapperProbe = homePkgs.callPackage ../../owned-agents/chatgpt {
    chatgpt-unwrapped = chatgptWrapperProbeUnwrapped;
    commandLineArgs = "--ozone-platform=wayland";
  };
in
assert !(builtins.pathExists chatgptGeneratedBytecodeDirectory);
pkgs.runCommand "desktop-app-support-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.dpkg
      pkgs.gnugrep
      pkgs.xdg-utils
    ];
  }
  ''
    set -eu

    # This archive is fetched independently from the ChatGPT derivation.  The
    # ASAR and its bundled Desktop Core companion are the vendor product, so
    # byte equality is the relevant contract rather than a source marker.
    pristine="$TMPDIR/pristine"
    dpkg-deb -x ${pristineArchive} "$pristine"
    if ! cmp -s \
      "$pristine/usr/lib/chatgpt/resources/app.asar" \
      ${chatgptUnwrapped}/lib/chatgpt/resources/app.asar; then
      echo 'packaged app.asar differs from the independently extracted vendor ASAR' >&2
      exit 1
    fi
    if ! cmp -s \
      "$pristine/usr/lib/chatgpt/resources/codex" \
      ${chatgptCompanion}; then
      echo 'packaged resources/codex differs from the vendor Desktop Core' >&2
      exit 1
    fi
    test -x ${chatgptCompanion}

    # Exercise the retained upstream Core in a private temporary home.  It
    # must not discover or attach to the persistent Remote Control owner.
    companion_home="$TMPDIR/companion-home"
    mkdir -p "$companion_home/home" "$companion_home/config" \
      "$companion_home/state" "$companion_home/cache" "$companion_home/codex"
    env \
      HOME="$companion_home/home" \
      XDG_CONFIG_HOME="$companion_home/config" \
      XDG_STATE_HOME="$companion_home/state" \
      XDG_CACHE_HOME="$companion_home/cache" \
      CODEX_HOME="$companion_home/codex" \
      DISABLE_AUTOUPDATER=1 \
      ${chatgptCompanion} --version | grep -E '^codex-cli [0-9]+'
    env \
      HOME="$companion_home/home" \
      XDG_CONFIG_HOME="$companion_home/config" \
      XDG_STATE_HOME="$companion_home/state" \
      XDG_CACHE_HOME="$companion_home/cache" \
      CODEX_HOME="$companion_home/codex" \
      DISABLE_AUTOUPDATER=1 \
      ${chatgptCompanion} app-server --listen stdio:// </dev/null
    if env \
      HOME="$companion_home/home" \
      XDG_CONFIG_HOME="$companion_home/config" \
      XDG_STATE_HOME="$companion_home/state" \
      XDG_CACHE_HOME="$companion_home/cache" \
      CODEX_HOME="$companion_home/codex" \
      DISABLE_AUTOUPDATER=1 \
      ${chatgptCompanion} app-server daemon version >/dev/null 2>&1; then
      echo 'vendor companion unexpectedly found a running owner in its private CODEX_HOME' >&2
      exit 1
    fi

    # Inspect the generated wrapper by invoking it with inherited vendor
    # selection variables.  It preserves those variables and Wayland launch
    # behavior; it does not force Desktop through the persistent owner.
    probe_output="$TMPDIR/chatgpt-wrapper-probe"
    CODEX_APP_SERVER_USE_LOCAL_DAEMON=vendor-choice \
      CODEX_CLI_PATH=vendor-cli \
      CODEX_APP_SERVER_FORCE_CLI=vendor-force-cli \
      CODEX_APP_SERVER_CLI_COMMAND=vendor-command \
      CODEX_APP_TOOLS_PIPE_PATH=vendor-app-tools \
      NIXOS_OZONE_WL=1 \
      WAYLAND_DISPLAY=wayland-test \
      CHATGPT_WRAPPER_PROBE_OUT="$probe_output" \
      ${chatgptWrapperProbe}/bin/chatgpt
    test "$(< "$probe_output")" = \
      'vendor-choice|vendor-cli|vendor-force-cli|vendor-command|vendor-app-tools|--ozone-platform=wayland --ozone-platform=wayland'

    touch "$out"
  ''
