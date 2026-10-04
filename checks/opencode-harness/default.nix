# OpenCode as the third harness: never asks for a permission, reports its
# sessions to Herdr with Herdr's own plugins, reads only its own skill tree,
# and, on the node that serves it, defaults to the local open-weight model.
{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  homeFor =
    capabilities:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        user = {
          size = "Min"; useColemak = false; hasPublicKey = false; gitSigningKey = "";
          matrixId = ""; isMultimediaDev = false; emailAddress = "opencode-harness-check@example.invalid";
          githubId = "opencode-harness-check"; name = "opencode-harness-check"; publicKeys = [ ];
        };
        horizon.node = {
          name = "opencode-harness-check";
          machine.architecture = "x86_64";
          inherit capabilities;
        };
        hexis = inputs.hexis.packages.${system}.default;
        rustToolchain = pkgs.rustc;
      };
      modules = [
        ../../modules/home/profiles/min/opencode-harness.nix
        {
          home = {
            username = "opencode-harness-check";
            homeDirectory = "/home/opencode-harness-check";
            stateVersion = "26.11";
          };
        }
      ];
    };
  served = (homeFor [ { kind = "openCodeTesting"; } ]).config;
  unserved = (homeFor [ ]).config;
  opencode = served.criomosHome.opencode.package;
  service = served.systemd.user.services.opencode-local-model.Service;
  configMerge = pkgs.writeText "opencode-config-merge" served.home.activation.mergeOpenCodeHarnessConfig.data;
  tuiMerge = pkgs.writeText "opencode-tui-merge" served.home.activation.mergeOpenCodeHarnessTuiConfig.data;
  unservedMerge = pkgs.writeText "opencode-unserved-merge" unserved.home.activation.mergeOpenCodeHarnessConfig.data;
  upstream = "${inputs.herdr}/src/integration/assets/opencode";
in
assert builtins.elem opencode served.home.packages;
assert !(unserved.systemd.user.services ? opencode-local-model);
assert lib.hasInfix "--sleep-idle-seconds" (toString service.ExecStart);
assert lib.hasInfix "--host 127.0.0.1" (toString service.ExecStart);
pkgs.runCommand "opencode-harness"
  {
    nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.gnugrep ];
  }
  ''
    set -eu
    run() { "$@"; }
    export DRY_RUN_CMD=""
    export HOME="$TMPDIR/home"

    # The wrapper keeps OpenCode on its own generated skill tree.
    grep -q 'OPENCODE_DISABLE_EXTERNAL_SKILLS' ${opencode}/bin/opencode
    ${opencode}/bin/opencode --version | grep -q '${pkgs.opencode.version}'

    # A user configuration holding a retired client-local plugin and a key of
    # its own: the declared keys win, the foreign key stays.
    mkdir -p "$HOME/.config/opencode"
    cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
    {"$schema":"https://opencode.ai/config.json","plugin":["/nix/store/retired-agent-intercom/plugin.mjs"],"permission":{"bash":"ask"},"theme":"kept"}
    JSON
    cat > "$HOME/.config/opencode/tui.json" <<'JSON'
    {"plugin":["/nix/store/retired-agent-intercom/tui.mjs"],"theme":"kept"}
    JSON
    bash ${configMerge}
    bash ${tuiMerge}
    config="$HOME/.config/opencode/opencode.json"
    tui="$HOME/.config/opencode/tui.json"
    test "$(jq -r '.permission' "$config")" = allow
    test "$(jq -r '.theme' "$config")" = kept
    test "$(jq -r '.plugin | length' "$config")" = 1
    test "$(jq -r '.autoupdate' "$config")" = false
    test "$(jq -r '.share' "$config")" = disabled
    test "$(jq -r '.model' "$config")" = criomos-local/qwen3.6-35b-a3b
    test "$(jq -r '.provider."criomos-local".options.baseURL' "$config")" = http://127.0.0.1:11435/v1
    test "$(jq -r '.provider."criomos-local".models."qwen3.6-35b-a3b".tool_call' "$config")" = true
    test "$(jq -r '.plugin | length' "$tui")" = 1
    test "$(jq -r '.theme' "$tui")" = kept

    # The plugins are the pinned Herdr's own assets, byte for byte.
    cmp "$(jq -r '.plugin[0]' "$config")" ${upstream}/herdr-agent-state.js
    cmp "$(jq -r '.plugin[0]' "$tui")" ${upstream}/herdr-tui-session.js

    # Re-asserted after drift.
    jq '.permission = {"bash":"ask"}' "$config" > "$config.drift" && mv "$config.drift" "$config"
    bash ${configMerge}
    test "$(jq -r '.permission' "$config")" = allow

    # A node that does not serve the local model declares no model or provider.
    export HOME="$TMPDIR/unserved"
    mkdir -p "$HOME/.config/opencode"
    bash ${unservedMerge}
    test "$(jq -r '.permission' "$HOME/.config/opencode/opencode.json")" = allow
    test "$(jq -r 'has("model") or has("provider")' "$HOME/.config/opencode/opencode.json")" = false

    touch "$out"
  ''
