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
  claudeDesktopPackage = ownedAgentPackages.claudeDesktopPackage;
  claudeSourceData = builtins.fromJSON (
    builtins.readFile ../../owned-agents/claude-desktop/hashes.json
  );
  claudePristineArchive = pkgs.fetchurl {
    url = claudeSourceData.urls.${system} or (throw "Unsupported Claude Desktop platform: ${system}");
    hash =
      claudeSourceData.hashes.${system} or (throw "Unsupported Claude Desktop platform: ${system}");
  };
  chatgptGeneratedBytecodeDirectory = ../../owned-agents/chatgpt/__pycache__;
  chatgptRetiredPatcher = ../../owned-agents/chatgpt/patch-asar.py;
  chatgptWrapperProbeUnwrapped =
    pkgs.runCommand "chatgpt-wrapper-probe-unwrapped"
      {
        passthru.version = source.version;
      }
      ''
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
assert !(builtins.pathExists chatgptRetiredPatcher);
pkgs.runCommand "desktop-app-support-contract"
  {
    nativeBuildInputs = [
      pkgs.asar
      pkgs.coreutils
      pkgs.diffutils
      pkgs.dpkg
      pkgs.gnutar
      pkgs.gnugrep
      pkgs.nodejs
      pkgs.python3
      pkgs.xdg-utils
    ];
  }
  ''
    set -eu

    # stdenv runs with pipefail, so a pipeline that ends in diff's expected
    # exit 1 would stop this script without a word. Every stop names its line
    # and command.
    trap 'echo "desktop-app-support: stopped at line $LINENO: $BASH_COMMAND" >&2' ERR

    # Claude Desktop keeps its vendor application archive except for the one
    # keep-awake call: Chromium before 157.0.8092 turns it into a Wayland idle
    # inhibitor that cancels the idle lock. The packaged archive differs from
    # the vendor archive in that call alone, and calls powerSaveBlocker.start
    # nowhere.
    claude_pristine="$TMPDIR/claude-pristine"
    claude_packaged="$TMPDIR/claude-packaged"
    mkdir -p "$claude_pristine"
    dpkg-deb --fsys-tarfile ${claudePristineArchive} \
      | tar --extract --directory "$claude_pristine" \
        --wildcards './usr/lib/claude-desktop/resources/app.asar*'
    claude_resources="$claude_pristine/usr/lib/claude-desktop/resources"
    ${pkgs.asar}/bin/asar extract "$claude_resources/app.asar" "$claude_pristine/app"
    ${pkgs.asar}/bin/asar extract \
      ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar "$claude_packaged"
    if grep -rIE 'powerSaveBlocker\.start' "$claude_packaged"; then
      echo 'packaged Claude Desktop still calls powerSaveBlocker.start' >&2
      exit 1
    fi
    test "$(grep -rIo 'powerSaveBlocker\.start("prevent-app-suspension")' "$claude_pristine/app" | wc -l)" = 1
    # The fixup phase rewrites the unpacked ELF files, so only the archive's
    # other files are compared.
    # diff exits 1 when the trees differ, which is expected, and 2 on trouble.
    claude_diff="$TMPDIR/claude-diff"
    diff_status=0
    diff -rq "$claude_pristine/app" "$claude_packaged" > "$claude_diff" || diff_status=$?
    if [ "$diff_status" -gt 1 ]; then
      echo "diff of the Claude archives failed with status $diff_status" >&2
      exit 1
    fi
    if grep -v '^Files ' "$claude_diff"; then
      echo 'packaged Claude Desktop adds or drops files against the vendor archive' >&2
      exit 1
    fi
    : > "$TMPDIR/claude-differing"
    sed -n 's/^Files \(.*\) and .* differ$/\1/p' "$claude_diff" > "$TMPDIR/claude-differing-all"
    while read -r vendor_file; do
      if ! head -c 4 "$vendor_file" | grep -q ELF; then
        echo "$vendor_file" >> "$TMPDIR/claude-differing"
      fi
    done < "$TMPDIR/claude-differing-all"
    if [ "$(wc -l < "$TMPDIR/claude-differing")" != 1 ]; then
      echo 'packaged Claude Desktop differs from the vendor archive in other than one non-ELF file:' >&2
      cat "$TMPDIR/claude-differing" >&2
      exit 1
    fi
    node ${./claude-desktop-asar-contract.cjs} \
      ${claudeDesktopPackage}/lib/claude-desktop/resources/app.asar
    if ! grep -qE '/\.vite/build/index\.chunk-[A-Za-z0-9_-]+\.js$' "$TMPDIR/claude-differing"; then
      echo 'the one differing Claude file is not the index.chunk-*.js file:' >&2
      cat "$TMPDIR/claude-differing" >&2
      exit 1
    fi

    # This archive is fetched independently from the ChatGPT derivation. The
    # bundled Desktop Core remains byte-identical vendor product. The ASAR
    # differs at exactly one byte-length-preserving guard: the Linux
    # process.report access that reaches Node's witnessed Git-worker SIGILL.
    pristine="$TMPDIR/pristine"
    dpkg-deb -x ${pristineArchive} "$pristine"
    expected_asar="$TMPDIR/expected-app.asar"
    cp "$pristine/usr/lib/chatgpt/resources/app.asar" "$expected_asar"
    python3 - "$expected_asar" <<'PY'
    from pathlib import Path
    import sys

    asar = Path(sys.argv[1])
    source = asar.read_bytes()
    target = b"isLinux() && process.report"
    replacement = b"false /* nix:skip report */"
    if source.count(target) != 1 or len(target) != len(replacement):
        raise SystemExit("vendor ASAR no longer has the exact process-report guard")
    asar.write_bytes(source.replace(target, replacement))
    PY
    if ! cmp -s "$expected_asar" ${chatgptUnwrapped}/lib/chatgpt/resources/app.asar; then
      echo 'packaged app.asar differs from the vendor ASAR beyond the documented process-report guard' >&2
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
