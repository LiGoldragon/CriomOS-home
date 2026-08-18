{ inputs, pkgs, ... }:

let
  lib = pkgs.lib;
  minProfile = builtins.readFile ../../modules/home/profiles/min/default.nix;
  spawnAction = executable: argument: {
    command = [
      executable
      argument
    ];
  };
  niriModuleResult = import ../../modules/home/profiles/min/niri.nix {
    inherit inputs lib pkgs;
    config.lib.niri.actions.spawn = spawnAction;
    constants = inputs.criomos-lib.lib.constants;
    horizon.node.behavesAs.edge = true;
    user.useFastRepeat = true;
  };
  niriModule =
    if niriModuleResult ? content then niriModuleResult.content else niriModuleResult;
  terminalBinding = niriModule.programs.niri.settings.binds."Mod+Shift+Return".action.command;
in
assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix "dconf.settings.\"org/gnome/desktop/interface\".gtk-enable-primary-paste = true;" minProfile)
  "The minimum desktop profile must retain GTK primary-selection paste for Ghostty";
assert lib.assertMsg
  (terminalBinding == [ "${pkgs.ghostty}/bin/ghostty" "--gtk-single-instance=true" ])
  "Mod+Shift+Return must use Ghostty's GTK singleton, so its new window inherits the focused terminal working directory";
pkgs.runCommand "ghostty-primary-selection" {
  terminalBinding = lib.concatStringsSep "\n" terminalBinding;
} ''
  test "$terminalBinding" = '${pkgs.ghostty}/bin/ghostty
--gtk-single-instance=true'
  touch "$out"
''
