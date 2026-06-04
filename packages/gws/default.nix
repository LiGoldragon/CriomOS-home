{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;

  gws = inputs.google-workspace-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
  gopass = "${pkgs.gopass}/bin/gopass";
in
pkgs.symlinkJoin {
  name = "gws";
  paths = [ gws ];
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
    wrapProgram $out/bin/gws \
      --prefix PATH : ${lib.makeBinPath [ pkgs.gopass ]} \
      --run 'if [ -z "''${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-}" ]; then export GOOGLE_WORKSPACE_CLI_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/gws"; fi' \
      --run 'export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND="''${GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND:-file}"' \
      --run 'if [ -z "''${GOOGLE_WORKSPACE_CLI_CLIENT_ID:-}" ]; then value="$(${gopass} show -o google-workspace/gws/client-id 2>/dev/null || true)"; if [ -n "$value" ]; then export GOOGLE_WORKSPACE_CLI_CLIENT_ID="$value"; fi; unset value; fi' \
      --run 'if [ -z "''${GOOGLE_WORKSPACE_CLI_CLIENT_SECRET:-}" ]; then value="$(${gopass} show -o google-workspace/gws/client-secret 2>/dev/null || true)"; if [ -n "$value" ]; then export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="$value"; fi; unset value; fi'
  '';

  meta = gws.meta // {
    description = "Google Workspace CLI with CriomOS gopass-aware OAuth client wrapper";
    mainProgram = "gws";
  };
}
