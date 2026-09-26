{ inputs, pkgs, ... }:
let
  messengerClj = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  compatibilityCommands = [
    "hm-send"
    "hm-send-abrupt"
    "hm-list"
    "hm-register"
    "hm-repair"
    "hm-deregister"
    "hm-rebind"
    "hm-move"
    "hm-retire"
    "hm-heartbeat-state"
  ];
in
pkgs.runCommand "messenger-clj-home-package" { } ''
  test -x ${messengerClj}/bin/messenger-clj
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command: "test -x ${messengerClj}/bin/${command}"
  ) compatibilityCommands}
  touch "$out"
''
