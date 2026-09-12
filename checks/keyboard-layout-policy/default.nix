{
  inputs,
  pkgs,
  ...
}:

let
  lib = pkgs.lib;
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
    textScale.fontPt = 12;
    user = {
      useFastRepeat = true;
      size.min = true;
    };
  };

  niriModuleContent =
    if niriModuleResult ? content then niriModuleResult.content else niriModuleResult;
  keyboardXkb = niriModuleContent.programs.niri.settings.input.keyboard.xkb;
in
assert lib.assertMsg (
  keyboardXkb.layout == "us"
) "Niri must keep the compositor layout at plain US";
assert lib.assertMsg (
  !(builtins.hasAttr "variant" keyboardXkb)
) "Niri must not apply a global Colemak XKB variant";
assert lib.assertMsg (
  keyboardXkb.options == "ctrl:nocaps,altwin:swap_ralt_rwin"
) "Niri must preserve existing non-layout XKB options";

pkgs.runCommand "keyboard-layout-policy-check" { } ''
  touch "$out"
''
