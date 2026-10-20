{ inputs, pkgs, ... }:
let
  messengerClj = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  commands = [
    "messenger-clj"
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
  configuration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        name = "messenger-check";
        size = "Min";
      };
    };
    modules = [
      ../../modules/home/profiles/min/messenger-clj.nix
      {
        home = {
          username = "messenger-check";
          homeDirectory = "/tmp/messenger-check";
          stateVersion = "26.05";
        };
      }
    ];
  };
  homePath = configuration.config.home.path;
  declaredFiles = builtins.attrNames configuration.config.home.file;
in
# The commands come from the Home profile alone; no file under ~/.local/bin is declared.
assert builtins.elem messengerClj configuration.config.home.packages;
assert !(builtins.any (name: pkgs.lib.hasPrefix ".local/bin/" name) declaredFiles);
pkgs.runCommand "messenger-clj-home-package" { } ''
  set -eu
  ${pkgs.lib.concatMapStringsSep "\n  " (command: ''
    test -x ${messengerClj}/bin/${command}
    test "$(readlink -f ${homePath}/bin/${command})" = "$(readlink -f ${messengerClj}/bin/${command})"
  '') commands}
  touch "$out"
''
