{
  inputs,
  pkgs,
  ...
}:
let
  lib = pkgs.lib;

  moduleResult = import ../../modules/home/profiles/min/dictation.nix {
    inherit inputs lib pkgs;
    config.lib.niri.actions.spawn = executable: argument: {
      command = [
        executable
        argument
      ];
    };
    horizon.node.behavesAs.edge = true;
    user.size.min = true;
  };

  moduleContent = if moduleResult ? content then moduleResult.content else moduleResult;

  binds = moduleContent.programs.niri.settings.binds;

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
    (checkBinding "Mod+Shift+V" "toggle")
    (checkBinding "Mod+Ctrl+V" "cancel")
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "whisrs-dictation-bindings" { } ''
    printf 'whisrs dictation bindings checked\n' > "$out"
  ''
