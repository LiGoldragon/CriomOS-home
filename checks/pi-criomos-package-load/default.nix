{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi = inputs.self.packages.${system}.pi;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-continue = inputs.self.packages.${system}.pi-continue;
in
pkgs.runCommand "pi-criomos-package-load"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    set -eu

    export HOME="$TMPDIR/home"
    export PI_PACKAGE_DIR="${pi}/lib/pi-monorepo/packages/coding-agent"

    mkdir -p "$HOME/.pi/agent"

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
      "theme": "criomos-dark",
      "packages": []
    }
    JSON

    test ! -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts"

    ${pi}/bin/pi \
      --list-models gpt > "$TMPDIR/models" 2>&1

    grep -E "local-test[[:space:]]+gpt-test" "$TMPDIR/models"

    printf '{"type":"get_commands"}\n' | ${pi}/bin/pi \
      --mode rpc \
      --no-session \
      --no-context-files \
      --no-skills \
      -e "${pi-continue}/share/pi-packages/pi-continue/extensions/continue/index.ts" \
      > "$TMPDIR/continue-commands" 2>&1

    grep -F '"name":"continue"' "$TMPDIR/continue-commands"

    touch "$out"
  ''
