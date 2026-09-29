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
  legacyMessengerPackage = "/nix/store/p8mz1msm8lxiahnw6sfipi8m258x1q3z-messenger-clj-0.2.5";
in
{
  config = lib.mkIf (sizeAtLeast "Min" && system == "x86_64-linux") {
    home = {
      packages = [ messengerCljPackage ];

      # These paths predate Home ownership.  They are first on PATH, so leave
      # no old shim in front of the immutable package that Home installs.
      file = lib.genAttrs (map (command: ".local/bin/${command}") managedCommands) (path: {
        source = "${messengerCljPackage}/bin/${lib.removePrefix ".local/bin/" path}";
        executable = true;
        force = true;
      });

      activation.retireProvenLegacyMessengerBindings = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
        set -eu
        legacy_package=${lib.escapeShellArg legacyMessengerPackage}
        for command in ${lib.escapeShellArgs managedCommands}; do
          target="$HOME/.local/bin/$command"
          if [ -e "$target" ] || [ -L "$target" ]; then
            if [ ! -L "$target" ] || [ "$(readlink -f "$target")" != "$legacy_package/bin/$command" ]; then
              echo "refusing to replace non-legacy messenger binding: $target" >&2
              exit 1
            fi
          fi
        done
      '';
    };
  };
}
