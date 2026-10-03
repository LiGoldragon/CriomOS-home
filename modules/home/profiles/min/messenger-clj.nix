{
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  system = pkgs.stdenv.hostPlatform.system;
  messengerCljPackage = inputs.messenger-clj.packages.${system}.default;
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
  managedCommands = [ "messenger-clj" ] ++ compatibilityCommands;
in
{
  config = lib.mkIf (sizeAtLeast "Min" && system == "x86_64-linux") {
    home = {
      packages = [ messengerCljPackage ];

      # Home owns these PATH-first bindings. Home Manager's own
      # checkLinkTargets step replaces a link into any Home Manager generation
      # and refuses a differing file or link of any other origin, so no shim
      # stands in front of the package and nothing foreign is clobbered.
      file = lib.genAttrs (map (command: ".local/bin/${command}") managedCommands) (path: {
        source = "${messengerCljPackage}/bin/${lib.removePrefix ".local/bin/" path}";
        executable = true;
      });
    };
  };
}
