{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi = inputs.self.packages.${system}.pi;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-continue = inputs.self.packages.${system}.pi-continue;
  pi-session-namer = inputs.self.packages.${system}.pi-session-namer;
in
pkgs.runCommand "pi-criomos-package-load"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    set -eu

    export HOME="$TMPDIR/home"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    export PI_PACKAGE_DIR="${pi}/lib/pi-monorepo/packages/coding-agent"

    mkdir -p "$HOME/.pi/agent/packages" "$XDG_RUNTIME_DIR"
    ln -s "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md" \
      "$HOME/.pi/agent/SYSTEM.md"
    ln -s "${pi-session-namer}/share/pi-packages/pi-session-namer" \
      "$HOME/.pi/agent/packages/pi-session-namer"

    cat > "$HOME/.pi/agent/models.json" <<'JSON'
    {
      "providers": {
        "local-test": {
          "api": "openai-completions",
          "baseUrl": "http://127.0.0.1:1/v1",
          "apiKey": "sk-test",
          "models": [
            {
              "id": "gpt-test",
              "name": "GPT Test",
              "reasoning": false,
              "input": ["text"],
              "contextWindow": 1024,
              "maxTokens": 128
            }
          ]
        }
      }
    }
    JSON

    cat > "$HOME/.pi/agent/settings.json" <<'JSON'
    {
      "defaultProvider": "local-test",
      "defaultModel": "gpt-test",
      "enabledModels": ["local-test/gpt-test"],
      "theme": "criomos-light/criomos-dark",
      "packages": [
        "${pi-criomos}/share/pi-packages/pi-criomos",
        "packages/pi-session-namer"
      ]
    }
    JSON

    test -f "${pi-session-namer}/share/pi-packages/pi-session-namer/index.ts"
    test -f "${pi-session-namer}/share/pi-packages/pi-session-namer/package.json"

    test -f "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    test -f "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/skills/pi-internals/SKILL.md"
    grep -q -F 'The concrete tool schemas, availability, and permission rules are authoritative.' \
      "${pi-criomos}/share/pi-packages/pi-criomos/system/SYSTEM.md"
    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"
    ! grep -q -E 'current-mode|theme-switcher|setTimeout|setInterval|watchFile|fs\.watch' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'PI_LIVE_THEME_CONTROL_REGISTRY_DIRECTORY' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'randomUUID' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'registryEntryExtension = ".path"' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'useActiveContext' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'containExternalCallback' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'ctx.ui.getTheme(selection.themeName)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    grep -q -F 'ctx.ui.setTheme(themeInstance)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'ctx.ui.setTheme(selection.themeName)' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'this.ctx.ui.' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'theme socket registered' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"
    ! grep -q -F 'pi-live-theme.sock' \
      "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts"

    ${pi}/bin/pi \
      --list-models gpt > "$TMPDIR/models" 2>&1

    grep -q -E "local-test[[:space:]]+gpt-test" "$TMPDIR/models"

    ${pi}/bin/pi list > "$TMPDIR/packages" 2>&1
    grep -q -F 'packages/pi-session-namer' "$TMPDIR/packages"

    set +e
    ${pi}/bin/pi \
      --mode text \
      --no-context-files \
      --no-skills \
      --model local-test/gpt-test \
      'Fix CriomOS package load smoke' \
      > "$TMPDIR/session-namer-out" 2> "$TMPDIR/session-namer-err"
    session_namer_status=$?
    set -e
    test "$session_namer_status" -ne 0
    ! grep -q -F 'Failed to load extension' "$TMPDIR/session-namer-err"
    grep -R -q -F '"name":"Fix CriomOS Package Load Smoke"' "$HOME/.pi/agent/sessions"

    printf '{"type":"get_commands"}\n' | ${pi}/bin/pi \
      --mode rpc \
      --no-context-files \
      --no-skills \
      -e "${pi-criomos}/share/pi-packages/pi-criomos/extensions/live-theme-control.ts" \
      > "$TMPDIR/live-theme-control-rpc" 2>&1

    grep -q -F '"statusKey":"live-theme-control"' "$TMPDIR/live-theme-control-rpc"
    grep -q -F '"success":true' "$TMPDIR/live-theme-control-rpc"

    printf '{"type":"get_commands"}\n' | ${pi}/bin/pi \
      --mode rpc \
      --no-session \
      --no-context-files \
      --no-skills \
      -e "${pi-continue}/share/pi-packages/pi-continue/extensions/continue/index.ts" \
      > "$TMPDIR/continue-commands" 2>&1

    grep -q -F '"name":"continue"' "$TMPDIR/continue-commands"

    touch "$out"
  ''
