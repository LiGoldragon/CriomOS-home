{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  homePkgs = pkgs.extend (pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; }));
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix {
    pkgs = homePkgs;
    inherit inputs;
    chatgptCommandLineArgs = "--ozone-platform=wayland";
  };
  mkConfiguration =
    horizon: user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = homePkgs;
      extraSpecialArgs = {
        inherit
          inputs
          horizon
          user
          ownedAgentPackages
          ;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        ({ ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; })
        ../../modules/home/core-packages.nix
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
    size = {
      min = true;
      medium = true;
    };
  };
  minUser = {
    name = "test-user";
    size.min = true;
  };
  mkHorizon = edge: user: {
    users.test-user = user;
    node = {
      name = "desktop-app-fixture";
      behavesAs.edge = edge;
      services = [ ];
    };
  };
  edgeMedium = mkConfiguration (mkHorizon true mediumUser) mediumUser;
  nonEdgeMedium = mkConfiguration (mkHorizon false mediumUser) mediumUser;
  edgeMin = mkConfiguration (mkHorizon true minUser) minUser;
  profile = pkgs.buildEnv {
    name = "desktop-app-support-profile";
    paths = edgeMedium.home.packages;
  };
  codexCliPackage = ownedAgentPackages.codexPackage;
  claudeCodePackage = ownedAgentPackages.claudeCodePackage;
  claudeDesktopPackage = ownedAgentPackages.claudeDesktopPackage;
  chatgptPackage = ownedAgentPackages.chatgptPackage;
  chatgptCandidate = "${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/codex";
  chatgptWrapperProbeUnwrapped =
    pkgs.runCommand "chatgpt-wrapper-probe-unwrapped"
      {
        passthru.version = "0";
      }
      ''
        mkdir -p "$out/bin" "$out/share"
        printf '%s\n' \
          '#!${pkgs.runtimeShell}' \
          'printf "%s|%s|%s|%s|%s" "''${CODEX_APP_SERVER_USE_LOCAL_DAEMON-}" "''${CODEX_CLI_PATH-}" "''${CODEX_APP_SERVER_FORCE_CLI-}" "''${CODEX_APP_SERVER_CLI_COMMAND-}" "''${CODEX_APP_TOOLS_PIPE_PATH-}" > "$CHATGPT_WRAPPER_PROBE_OUT"' \
          > "$out/bin/chatgpt"
        chmod +x "$out/bin/chatgpt"
      '';
  chatgptWrapperProbe = homePkgs.callPackage ../../owned-agents/chatgpt {
    codexPackage = codexCliPackage;
    chatgpt-unwrapped = chatgptWrapperProbeUnwrapped;
  };
  claudeDesktopEntry = edgeMedium.xdg.dataFile."applications/claude-desktop.desktop".source;
  claudeDesktopDefault = builtins.head (
    edgeMedium.xdg.mimeApps.defaultApplications."x-scheme-handler/claude"
  );
  chatgptEntry = edgeMedium.xdg.dataFile."applications/chatgpt.desktop".source;
  chatgptDefault = builtins.head (
    edgeMedium.xdg.mimeApps.defaultApplications."x-scheme-handler/codex"
  );
  chatgptLauncher = lib.removeSuffix "/share/applications/chatgpt.desktop" (toString chatgptEntry);
in
assert claudeDesktopPackage.passthru.declaredClaudeCode == claudeCodePackage;
assert chatgptPackage.passthru.codexPackage == codexCliPackage;
assert builtins.elem system claudeDesktopPackage.meta.platforms;
assert builtins.elem system chatgptPackage.meta.platforms;
assert claudeDesktopEntry == "${claudeDesktopPackage}/share/applications/claude-desktop.desktop";
assert claudeDesktopDefault == "claude-desktop.desktop";
assert chatgptDefault == "chatgpt.desktop";
assert !(nonEdgeMedium.xdg.dataFile ? "applications/claude-desktop.desktop");
assert !(nonEdgeMedium.xdg.mimeApps.defaultApplications ? "x-scheme-handler/claude");
assert !(nonEdgeMedium.xdg.dataFile ? "applications/chatgpt.desktop");
assert !(nonEdgeMedium.xdg.mimeApps.defaultApplications ? "x-scheme-handler/codex");
assert !(edgeMin.xdg.dataFile ? "applications/claude-desktop.desktop");
assert edgeMin.systemd.user.services ? codex-remote-control;
pkgs.runCommand "desktop-app-support-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.binutils
      pkgs.desktop-file-utils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.nodejs
      pkgs.python3
      pkgs.xdg-utils
      profile
    ];
  }
  ''
    set -eu

    test "$( ${profile}/bin/codex --version )" = 'codex-cli ${codexCliPackage.version}'
    test "$( ${profile}/bin/claude --version )" = '${claudeCodePackage.version} (Claude Code)'
    test -x ${profile}/bin/chatgpt
    test -x ${profile}/bin/claude-desktop

    test -f ${claudeDesktopEntry}
    grep -Fx 'Exec=claude-desktop %U' ${claudeDesktopEntry}
    grep -Fx 'MimeType=x-scheme-handler/claude' ${claudeDesktopEntry}
    test -f ${chatgptEntry}
    grep -E '^Exec=.*chatgpt' ${chatgptEntry}
    grep -F 'x-scheme-handler/codex' ${chatgptEntry}
    test -x ${chatgptLauncher}/bin/chatgpt
    probe_output="$TMPDIR/chatgpt-wrapper-probe"
    CODEX_CLI_PATH=must-not-select-stdio \
      CODEX_APP_SERVER_FORCE_CLI=must-not-select-stdio \
      CODEX_APP_SERVER_CLI_COMMAND=must-not-select-stdio \
      CODEX_APP_TOOLS_PIPE_PATH=must-not-create-private-channel \
      CHATGPT_WRAPPER_PROBE_OUT="$probe_output" \
      ${chatgptWrapperProbe}/bin/chatgpt
    test "$(< "$probe_output")" = '1||||'
    if ! test -x ${chatgptCandidate}; then
      echo "ChatGPT local-daemon resolver candidate is missing: ${chatgptCandidate}" >&2
      exit 1
    fi
    test "$(env -u CODEX_CLI_PATH ${chatgptCandidate} --version)" = 'codex-cli ${codexCliPackage.version}'
    strings ${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/app.asar | grep -F 'getConfigOverrides:()=>[]'
    strings ${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/app.asar | grep -F 'async function Pge(){return[]}'

    # Parse the entire generated ASAR header and ask Node to parse every
    # packed JavaScript payload. This verifies the actual packaged artifact,
    # rather than just the small source fixture below.
    asar_js_dir="$TMPDIR/chatgpt-asar-js"
    mkdir -p "$asar_js_dir"
    ${pkgs.python3}/bin/python - ${chatgptPackage.passthru.unwrapped}/lib/chatgpt/resources/app.asar "$asar_js_dir" <<'PY'
    import json
    import pathlib
    import sys

    asar_path = pathlib.Path(sys.argv[1])
    output_dir = pathlib.Path(sys.argv[2])
    blob = asar_path.read_bytes()
    # ASAR stores the padded header size at bytes 4..8 and the JSON payload
    # size at bytes 12..16.  The padding between JSON and payload is part of
    # the header, so using json_size as the payload offset misaligns every
    # extracted JavaScript file by nine bytes in this package.
    header_size = int.from_bytes(blob[4:8], "little")
    json_size = int.from_bytes(blob[12:16], "little")
    header = json.loads(blob[16 : 16 + json_size])
    payload_offset = 8 + header_size
    paths = []

    def visit(node, path=""):
        for name, entry in node.get("files", {}).items():
            child_path = f"{path}/{name}"
            if "files" in entry:
                visit(entry, child_path)
            elif child_path.endswith(".js") and not entry.get("unpacked", False):
                offset = payload_offset + int(entry["offset"])
                contents = blob[offset : offset + entry["size"]]
                assert len(contents) == entry["size"], child_path
                destination = output_dir / f"{len(paths)}.js"
                destination.write_bytes(contents)
                paths.append(destination)

    visit(header)
    assert paths
    (output_dir / "paths").write_text("\n".join(map(str, paths)) + "\n")
    PY
    while IFS= read -r asar_js; do
      ${pkgs.nodejs}/bin/node --check "$asar_js"
    done < "$asar_js_dir/paths"

    # Patching is byte-length preserving, so the replacement must consume the
    # original function's closing brace. Exercise the complete patch pipeline
    # on the exact matched JS shapes and ask Node to parse the result.
    patch_fixture="$TMPDIR/chatgpt-asar-patch.js"
    cat > "$patch_fixture" <<'EOF'
    isLinux() && process.report;
    async function ab(e,t){if(cd.default.platform===`darwin`){await ef(`/usr/bin/ditto`,[`--noqtn`,e,t]);return}if(cd.default.platform!==`win32`){await gh.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0});return}}
    const connection={getConfigOverrides:()=>Pge(e)};
    async function Pge({hostConfig:e,resourcesPath:t=process.resourcesPath}){/* ................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................ */return e}function YE(e){return ZZ.warning(`Codex app tools unavailable`)}
    EOF
    ${pkgs.python3}/bin/python ${../../owned-agents/chatgpt/patch-asar.py} "$patch_fixture"
    grep -F 'async function Pge(){return[]}' "$patch_fixture"
    ${pkgs.nodejs}/bin/node --check "$patch_fixture"

    # Composer constructs a flat codex_app enabled-tools setting after the
    # App Tools resolver has run.  The request boundary must remove that form
    # and the equivalent nested form for start, resume, and fork over both
    # local stdio and WebSocket, without disturbing unrelated configuration.
    composer_fixture="$TMPDIR/chatgpt-composer-transport.js"
    cat > "$composer_fixture" <<'EOF'
    isLinux() && process.report;
    async function ab(e,t){if(cd.default.platform===`darwin`){await ef(`/usr/bin/ditto`,[`--noqtn`,e,t]);return}if(cd.default.platform!==`win32`){await gh.default.cp(e,t,{recursive:!0,verbatimSymlinks:!0});return}}
    const connection={getConfigOverrides:()=>Pge(e)};
    async function Pge({hostConfig:e,resourcesPath:t=process.resourcesPath}){/* ................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................ */return e}function YE(e){return ZZ.warning(`Codex app tools unavailable`)}
    function _T(e){return Nge.warning(`Codex app tools unavailable for this Core launch`,{safe:{reason:e},sensitive:{}}),[`mcp_servers.codex_app={command="",enabled=false}`]}
    function mte(e,t,n){return e}
    function ai(e){return!0}
    function oi(e){return ui(e.params.config)}
    function gte(e,t){return`''${e}.''${t}`.replaceAll(`[`,`.`).replaceAll(`]`,``).replace(/["'\s]/gu,``).replace(/\.{2,}/gu,`.`).replace(/^\.|\.$/gu,``)}
    function li(e){return!(`id`in e)||!(`method`in e)?!1:e.method===`thread/start`||e.method===`thread/resume`||e.method===`thread/fork`}
    function ui(e){return typeof e===`object`&&!!e&&!Array.isArray(e)}
    function pte({getHostLifecycle:e,getExpectedThreadConfig:t,isLocalStdio:n}){if(n())return r=>n()?mte(r,li(r)&&ai(r)?e():null,t):r}
    async function cj({config:c,effort:r,client:d}){let h={config:{...c,"mcp_servers.codex_app":{enabled:!1,command:``},model_reasoning_effort:r}};return d.startThread(h)}
    async function h0({config:s,effort:r,client:f,sourceThreadId:c}){let v={...s,"mcp_servers.codex_app":{enabled:!1,command:``},model_reasoning_effort:r};return c==null?f.startThread({config:v}):f.forkThread({config:v})}
    function REi(e,t){return{...e,...t}}
    function PEn(e){return{"mcp_servers.codex_app.enabled_tools":e}}
    function _ca(e){return{config:REi(e,PEn([`normal-composer`]))}}
    function Rrn(e){return{method:`thread/start`,params:_ca(e)}}
    EOF
    composer_before_fixture="$TMPDIR/chatgpt-composer-transport-before.js"
    cp "$composer_fixture" "$composer_before_fixture"
    ${pkgs.nodejs}/bin/node - "$composer_before_fixture" <<'EOF'
    const assert = require(`assert`);
    const fs = require(`fs`);
    const vm = require(`vm`);
    const source = fs.readFileSync(process.argv[2], `utf8`);
    const context = { isLinux: () => false, process, console };
    vm.createContext(context);
    vm.runInContext(source, context);
    const unrelated = {
      "features.keep": true,
      "mcp_servers.other": { command: `keep` },
      mcp_servers: { other: { url: `https://example.invalid/mcp` } },
    };
    const request = context.Rrn(unrelated);
    assert.equal(
      Object.hasOwn(request.params.config, `mcp_servers.codex_app.enabled_tools`),
      true,
      `broken normal Composer path no longer reproduces flat codex_app leak`
    );
    console.log(`failing-before witness: normal Composer WebSocket request leaked flat enabled_tools`);
    EOF
    ${pkgs.python3}/bin/python ${../../owned-agents/chatgpt/patch-asar.py} "$composer_fixture"
    ${pkgs.nodejs}/bin/node --check "$composer_fixture"
    ${pkgs.nodejs}/bin/node - "$composer_fixture" <<'EOF'
    const assert = require(`assert`);
    const fs = require(`fs`);
    const vm = require(`vm`);
    const source = fs.readFileSync(process.argv[2], `utf8`);
    const context = { isLinux: () => false, process, console };
    vm.createContext(context);
    vm.runInContext(source, context);
    const hasCodexApp = config => config != null && typeof config === `object` && (
      Object.keys(config).some(key => key === `mcp_servers.codex_app` || key.startsWith(`mcp_servers.codex_app.`)) ||
      Object.hasOwn(config.mcp_servers ?? {}, `codex_app`)
    );
    const unrelated = {
      "features.keep": true,
      "mcp_servers.other": { command: `keep` },
      mcp_servers: { other: { url: `https://example.invalid/mcp` } },
    };
    const transports = [
      [ `stdio`, true ],
      [ `websocket`, false ],
    ];
    const methods = [ `thread/start`, `thread/resume`, `thread/fork` ];
    const forms = [
      [ `flat`, { ...unrelated, "mcp_servers.codex_app.enabled_tools": [ `private-tool` ] } ],
      [ `nested`, { ...unrelated, mcp_servers: { ...unrelated.mcp_servers, codex_app: { enabled: false, command: `` } } } ],
    ];
    for (const [transport, isLocalStdio] of transports) {
      const send = context.pte({ getHostLifecycle: () => null, getExpectedThreadConfig: () => ({}), isLocalStdio: () => isLocalStdio });
      for (const method of methods) for (const [form, config] of forms) {
        const request = send({ id: `''${transport}-''${method}-''${form}`, method, params: { config } });
        assert.equal(hasCodexApp(request.params.config), false, `''${transport} ''${method} ''${form} leaked codex_app`);
        assert.equal(request.params.config[`features.keep`], true);
        assert.equal(request.params.config[`mcp_servers.other`].command, `keep`);
        assert.equal(request.params.config.mcp_servers.other.url, `https://example.invalid/mcp`);
      }
    }
    const websocket = context.pte({ getHostLifecycle: () => null, getExpectedThreadConfig: () => ({}), isLocalStdio: () => false });
    const normalComposer = websocket(context.Rrn(unrelated));
    assert.equal(hasCodexApp(normalComposer.params.config), false, `normal Composer merge leaked flat enabled_tools`);
    assert.equal(normalComposer.params.config[`features.keep`], true);
    const captured = [];
    const client = {
      startThread: async params => { captured.push(websocket({ method: `thread/start`, params })); return { thread: { id: `start` } }; },
      forkThread: async params => { captured.push(websocket({ method: `thread/fork`, params })); return { thread: { id: `fork` } }; },
    };
    Promise.resolve()
      .then(() => context.cj({ config: unrelated, effort: `low`, client }))
      .then(() => context.h0({ config: unrelated, effort: `low`, client, sourceThreadId: null }))
      .then(() => context.h0({ config: unrelated, effort: `low`, client, sourceThreadId: `existing` }))
      .then(() => {
        assert.equal(captured.length, 3);
        for (const request of captured) assert.equal(hasCodexApp(request.params.config), false, `''${request.method} producer leaked codex_app`);
        console.log(`composer transport request contract passed`);
      });
    EOF

    # The Desktop client must reach the shared owner without injecting its
    # retired private App Tools MCP server.  Exercise the same app-server
    # operations it uses for both a new thread and a resumed rollout.
    codex_home="$TMPDIR/codex-home"
    mkdir -p "$codex_home"
    coproc codex_app_server {
      CODEX_HOME="$codex_home" DISABLE_AUTOUPDATER=1 ${codexCliPackage}/bin/codex \
        app-server --listen stdio://
    }
    trap 'kill "$codex_app_server_PID" 2>/dev/null || true; wait "$codex_app_server_PID" 2>/dev/null || true' EXIT
    codex_request() {
      printf '%s\n' "$1" >&"''${codex_app_server[1]}"
    }
    codex_response() {
      response_id="$1"
      response_file="$2"
      while IFS= read -r -t 20 response <&"''${codex_app_server[0]}"; do
        if printf '%s' "$response" | jq -e ".id == $response_id and .result != null" >/dev/null; then
          printf '%s\n' "$response" > "$response_file"
          return 0
        fi
      done
      return 1
    }
    codex_error() {
      response_id="$1"
      response_file="$2"
      while IFS= read -r -t 20 response <&"''${codex_app_server[0]}"; do
        if printf '%s' "$response" | jq -e ".id == $response_id and .error != null" >/dev/null; then
          printf '%s\n' "$response" > "$response_file"
          return 0
        fi
      done
      return 1
    }
    codex_request '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"desktop-app-support","version":"1"}}}'
    codex_response 1 "$TMPDIR/codex-app-server-initialize.json"
    codex_request '{"jsonrpc":"2.0","id":2,"method":"thread/start","params":{"cwd":"/tmp","config":{"mcp_servers.codex_app":{"enabled":false,"command":""}}}}'
    codex_error 2 "$TMPDIR/codex-app-server-invalid-codex-app.json"
    jq -e '.error.message | contains("invalid transport in mcp_servers.codex_app")' \
      "$TMPDIR/codex-app-server-invalid-codex-app.json" >/dev/null
    codex_request '{"jsonrpc":"2.0","id":3,"method":"thread/start","params":{"cwd":"/tmp","config":{}}}'
    codex_response 3 "$TMPDIR/codex-app-server-thread-start.json"
    thread_id="$(jq -r '.result.thread.id' "$TMPDIR/codex-app-server-thread-start.json")"
    test "$thread_id" != null
    codex_request "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"turn/start\",\"params\":{\"threadId\":\"$thread_id\",\"input\":[]}}"
    codex_response 4 "$TMPDIR/codex-app-server-turn-start.json"
    jq -e '.result.turn.status == "inProgress"' "$TMPDIR/codex-app-server-turn-start.json" >/dev/null
    codex_request "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"thread/resume\",\"params\":{\"threadId\":\"$thread_id\"}}"
    codex_response 5 "$TMPDIR/codex-app-server-thread-resume.json"
    jq -e --arg thread_id "$thread_id" '.result.thread.id == $thread_id' \
      "$TMPDIR/codex-app-server-thread-resume.json" >/dev/null
    kill "$codex_app_server_PID"
    wait "$codex_app_server_PID" || true
    trap - EXIT

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
