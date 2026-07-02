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
  listenerPackage = inputs.listener.packages.${pkgs.stdenv.hostPlatform.system}.default;
  listenerEnvironmentExample = moduleContent.xdg.configFile."listener/environment.example".text;

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

  commandRunsListenerCancel =
    command:
    builtins.length command == 2
    && commandRunsExecutable command "/bin/listener-cancel-capture"
    && builtins.elemAt command 1 == "cancel";

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
      condition = commandRunsListenerToggle (commandFor "Mod+Alt+M");
      message = "Mod+Alt+M must run listener-toggle-capture";
    }
    {
      condition = commandRunsListenerCancel (commandFor "Mod+Ctrl+Alt+M");
      message = "Mod+Ctrl+Alt+M must run listener-cancel-capture";
    }
    {
      condition = !(builtins.hasAttr "Mod+Alt+L" binds);
      message = "Mod+Alt+L must not remain a Listener binding";
    }
    {
      condition =
        listenerService ? EnvironmentFile
        && listenerService.EnvironmentFile == "-%h/.config/listener/environment";
      message = "listener.service must keep the local environment override file";
    }
    {
      condition = lib.versionAtLeast (listenerPackage.version or "0") "0.5.1";
      message = "Listener package must be version 0.5.1 or newer";
    }
    {
      condition = !(lib.hasInfix "LISTENER_TRANSCRIPTION_PROGRAM" listenerEnvironmentExample);
      message = "listener environment example must not point production at an external transcriber";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  let
    listenerToggleExecutable = builtins.elemAt (commandFor "Mod+Alt+M") 0;
    listenerCancelExecutable = builtins.elemAt (commandFor "Mod+Ctrl+Alt+M") 0;
  in
  pkgs.runCommand "listener-dictation-bindings" { } ''
    ${pkgs.bash}/bin/bash -n ${listenerService.ExecStart}
    ${pkgs.bash}/bin/bash -n ${listenerToggleExecutable}
    ${pkgs.bash}/bin/bash -n ${listenerCancelExecutable}

    if grep -F 'LISTENER_TRANSCRIPTION_PROGRAM=' ${listenerService.ExecStart} >/dev/null; then
      echo 'listener service wrapper must not export LISTENER_TRANSCRIPTION_PROGRAM' >&2
      exit 1
    fi
    if grep -F 'listener-openai-transcribe' ${listenerService.ExecStart} >/dev/null; then
      echo 'listener service wrapper must not reference listener-openai-transcribe' >&2
      exit 1
    fi
    if grep -F 'whisrs' ${listenerService.ExecStart} >/dev/null; then
      echo 'listener service wrapper must not invoke or reference whisrs' >&2
      exit 1
    fi
    grep -F 'LISTENER_CAPTURE_PROGRAM=' ${listenerService.ExecStart} >/dev/null
    grep -F 'LISTENER_CLIPBOARD_PROGRAM=' ${listenerService.ExecStart} >/dev/null
    grep -F '/bin/listener cancel "$session"' ${listenerCancelExecutable} >/dev/null
    grep -F 'read_active_listener_session' ${listenerCancelExecutable} >/dev/null
    if grep -E '/bin/listener (stop|transcribe)|listener-openai-transcribe|wl-copy|LISTENER_CLIPBOARD_PROGRAM' ${listenerCancelExecutable} >/dev/null; then
      echo 'listener cancel wrapper must not stop/transcribe/copy' >&2
      exit 1
    fi
    printf 'listener and whisrs dictation bindings checked\n' > "$out"
  ''
