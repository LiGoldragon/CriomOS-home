{ pkgs, inputs, ... }:
let
  profile = pkgs.callPackage ../../packages/harness-profile { inherit inputs; };
in
pkgs.runCommand "harness-home-profile-check" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  for name in flow flow-meta flow-nexus; do
    test "$(readlink -f ${profile}/bin/$name)" = "$(readlink -f ${profile.flow}/bin/$name)"
  done
  for name in message message-meta message-nexus; do
    test "$(readlink -f ${profile}/bin/$name)" = "$(readlink -f ${profile.message}/bin/$name)"
  done
  for name in flow-next flow-next-meta message-next message-next-meta message-daemon meta-message; do
    test ! -e "${profile}/bin/$name"
  done
  for path in ${profile.baseline}/bin/*; do
    name=$(basename "$path")
    case "$name" in flow*|message*|meta-message|curriculum|messenger-clj|hm-*) continue ;; esac
    test "$(readlink -f "$path")" = "$(readlink -f "${profile}/bin/$name")"
  done
  mkdir -p "$out"
''
