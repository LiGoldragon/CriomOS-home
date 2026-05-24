{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  pi = inputs.self.packages.${system}.pi;
  pi-criomos = inputs.self.packages.${system}.pi-criomos;
  pi-web-access = inputs.self.packages.${system}.pi-web-access;
in
pkgs.runCommand "pi-criomos-extension-load"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    set -eu

    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$TMPDIR/state"
    export PI_PACKAGE_DIR="${pi}/lib/pi-monorepo/packages/coding-agent"

    mkdir -p "$HOME/.pi/agent" "$XDG_STATE_HOME/chroma"
    echo light > "$XDG_STATE_HOME/chroma/current-mode"

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

    ${pi}/bin/pi \
      -e "${pi-criomos}/share/pi-packages/pi-criomos/src/extensions/theme-switcher.ts" \
      --list-models gpt > "$TMPDIR/models" 2>&1

    grep -E "local-test[[:space:]]+gpt-test" "$TMPDIR/models"

    ${pi}/bin/pi \
      -e "${pi-web-access}/share/pi-packages/pi-web-access/index.ts" \
      --list-models gpt > "$TMPDIR/web-models" 2>&1

    grep -E "local-test[[:space:]]+gpt-test" "$TMPDIR/web-models"

    touch "$out"
  ''
