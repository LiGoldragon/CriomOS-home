# Exact reviewed SessionStart proof hook. Trust does not install or execute it.
# The production Stop hook is not approved by this entry.
{ lib }:
let
  key = "/<session-flags>/config.toml:session_start:0:0";
  hash = "sha256:20b644af0253507ad98b20d6886b41a4db1846a3ab0bdf02ebd8a64038881b2e";
  command = "'/nix/store/bfqsxlviikq7vlp36kasy5hhamlxlkd2-nodejs-slim-24.19.0/bin/node' '/home/li/private-repos/flow-evidence/0c85a3/primary-committer-process-birth-20261012/source/tools/primary-committer/environment-proof.mjs' '/home/li/private-repos/flow-evidence/42265e/primary-committer-process-birth-seam-20261012/environment-proof.json'";
  pointer = lib.replaceStrings [ "~" "/" ] [ "~0" "~1" ] key;
in {
  inherit key hash command;
  declared.hooks.state.${key} = { enabled = true; trusted_hash = hash; };
  modes = {
    "/hooks/state/${pointer}/enabled" = "always";
    "/hooks/state/${pointer}/trusted_hash" = "always";
  };
}
