{ pkgs, inputs, ... }:
let
  activation = pkgs.callPackage ../../packages/primary-committer-hook-trust { inherit inputs; };
  trust = import ../../lib/primary-committer-hook-trust.nix { lib = pkgs.lib; };
  hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
in pkgs.runCommand "primary-committer-hook-trust-contract" {
  nativeBuildInputs = [ pkgs.yq-go pkgs.jq ];
} ''
  set -eu
  fixture="$TMPDIR/config.toml"
  printf '%s\n' 'model = "preserved-model"' 'unrelated = "preserved"' '[hooks.state."foreign"]' 'enabled = false' 'trusted_hash = "foreign-hash"' > "$fixture"
  ${hexis}/bin/hexis apply --file "$fixture" --declared ${activation.declared}
  yq -p toml -o json '.' "$fixture" > "$TMPDIR/result.json"
  jq -e --arg key ${pkgs.lib.escapeShellArg trust.key} --arg hash ${pkgs.lib.escapeShellArg trust.hash} '
    .model == "preserved-model" and .unrelated == "preserved" and
    .hooks.state.foreign.enabled == false and .hooks.state.foreign.trusted_hash == "foreign-hash" and
    .hooks.state[$key].enabled == true and .hooks.state[$key].trusted_hash == $hash
  ' "$TMPDIR/result.json"
  ${hexis}/bin/hexis apply --file "$fixture" --declared ${activation.declared}
  touch "$out"
''
