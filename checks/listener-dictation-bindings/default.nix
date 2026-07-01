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

  commandFor = key: binds.${key}.action.command or [ ];

  commandRunsExecutable =
    command: executableSuffix:
    builtins.length command >= 1 && lib.hasSuffix executableSuffix (builtins.elemAt command 0);

  commandRunsWhisrsSubcommand =
    command: expectedArgument:
    builtins.length command == 2
    && commandRunsExecutable command "/bin/whisrs"
    && builtins.elemAt command 1 == expectedArgument;

  commandRunsListenerToggle =
    command:
    builtins.length command == 2
    && commandRunsExecutable command "listener-toggle-capture"
    && builtins.elemAt command 1 == "toggle";

  checkWhisrsBinding =
    key: expectedArgument:
    let
      command = commandFor key;
    in
    {
      condition = commandRunsWhisrsSubcommand command expectedArgument;
      message = "${key} must remain whisrs ${expectedArgument}";
    };

  assertions = [
    (checkWhisrsBinding "Mod+V" "toggle-copy")
    (checkWhisrsBinding "Mod+Shift+V" "toggle")
    (checkWhisrsBinding "Mod+Ctrl+V" "cancel")
    {
      condition = commandRunsExecutable (commandFor "Mod+Alt+V") "whisrs-recall";
      message = "Mod+Alt+V must remain whisrs-recall";
    }
    {
      condition = commandRunsListenerToggle (commandFor "Mod+Alt+L");
      message = "Mod+Alt+L must run listener-toggle-capture";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "listener-dictation-bindings" { } ''
    printf 'listener and whisrs dictation bindings checked\n' > "$out"
  ''
