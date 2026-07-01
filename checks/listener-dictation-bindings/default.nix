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
  listenerService = moduleContent.systemd.user.services.listener.Service;

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
    && commandRunsExecutable command "/bin/listener-toggle-capture"
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
    {
      condition =
        listenerService ? EnvironmentFile
        && listenerService.EnvironmentFile == "-%h/.config/listener/environment";
      message = "listener.service must keep the local environment override file";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "listener-dictation-bindings" { } ''
    ${pkgs.bash}/bin/bash -n ${listenerService.ExecStart}
    grep -F 'LISTENER_TRANSCRIPTION_PROGRAM=' ${listenerService.ExecStart} >/dev/null
    grep -F 'listener-openai-transcribe' ${listenerService.ExecStart} >/dev/null
    if grep -F 'whisrs' ${listenerService.ExecStart} >/dev/null; then
      echo 'listener service wrapper must not invoke or reference whisrs' >&2
      exit 1
    fi
    transcriber="$(${pkgs.gnused}/bin/sed -n 's|^.*LISTENER_TRANSCRIPTION_PROGRAM=".*:-\([^}]*listener-openai-transcribe\)}"$|\1|p' ${listenerService.ExecStart})"
    test -x "$transcriber"
    ${pkgs.bash}/bin/bash -n "$transcriber"
    printf 'listener and whisrs dictation bindings checked\n' > "$out"
  ''
