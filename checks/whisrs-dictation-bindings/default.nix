{
  inputs,
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  spawnAction = executable: {
    command = [ executable ];
    __functor = _self: argument: {
      command = [
        executable
        argument
      ];
    };
  };

  moduleResult = import ../../modules/home/profiles/min/dictation.nix {
    inherit inputs lib pkgs;
    config.lib.niri.actions.spawn = spawnAction;
    horizon.node.behavesAs.edge = true;
    user.size.min = true;
  };

  moduleContent = if moduleResult ? content then moduleResult.content else moduleResult;

  binds = moduleContent.programs.niri.settings.binds;
  packageNames = map lib.getName moduleContent.home.packages;

  commandFor = key: binds.${key}.action.command or [ ];

  commandRunsWhisrsSubcommand =
    command: expectedArgument:
    builtins.length command == 2
    && lib.hasSuffix "/bin/whisrs" (builtins.elemAt command 0)
    && builtins.elemAt command 1 == expectedArgument;

  checkBinding =
    key: expectedArgument:
    let
      command = commandFor key;
    in
    {
      condition = commandRunsWhisrsSubcommand command expectedArgument;
      message = "${key} must run whisrs ${expectedArgument}";
    };

  assertions = [
    (checkBinding "Mod+V" "toggle-copy")
    {
      condition = !(builtins.hasAttr "Mod+Shift+V" binds);
      message = "Mod+Shift+V must stay unbound because direct insertion is unsafe";
    }
    (checkBinding "Mod+Ctrl+V" "cancel")
    {
      condition =
        let
          command = commandFor "Mod+Alt+V";
        in
        builtins.length command == 1 && lib.hasSuffix "whisrs-recall" (builtins.elemAt command 0);
      message = "Mod+Alt+V must run whisrs-recall";
    }
    {
      condition = !(builtins.elem "wtype" packageNames);
      message = "dictation profile must not expose wtype";
    }
    {
      condition = !(builtins.elem "hyprvoice" packageNames);
      message = "dictation profile must not expose Hyprvoice";
    }
    {
      condition = !(builtins.pathExists ../../packages/hyprvoice/default.nix);
      message = "packages/hyprvoice must not exist";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "whisrs-dictation-bindings" { } ''
    printf 'whisrs dictation bindings checked\n' > "$out"
  ''
