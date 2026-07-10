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
  listenerService = moduleContent.systemd.user.services.listener.Service;
  listenerPackage = inputs.listener.packages.${pkgs.stdenv.hostPlatform.system}.default;
  listenerEnvironmentExample = moduleContent.xdg.configFile."listener/environment.example".text;
  capturePolicy = moduleContent.xdg.configFile."wireplumber/wireplumber.conf.d/60-capture-policy.conf".text;
  keepalivePolicy = moduleContent.xdg.configFile."pipewire/pipewire.conf.d/60-dji-mic-keepalive.conf".text;

  commandFor = key: binds.${key}.action.command or [ ];

  commandRunsExecutable =
    command: executableSuffix:
    builtins.length command >= 1 && lib.hasSuffix executableSuffix (builtins.elemAt command 0);

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

  commandRunsListenerRecall =
    command: builtins.length command == 1 && commandRunsExecutable command "/bin/listener-recall";

  assertions = [
    {
      condition = commandRunsListenerToggle (commandFor "Mod+V");
      message = "Mod+V must run listener-toggle-capture";
    }
    {
      condition = commandRunsListenerCancel (commandFor "Mod+Ctrl+V");
      message = "Mod+Ctrl+V must run listener-cancel-capture";
    }
    {
      condition = commandRunsListenerRecall (commandFor "Mod+Alt+V");
      message = "Mod+Alt+V must run listener-recall";
    }
    {
      condition = !(builtins.hasAttr "Mod+Shift+V" binds);
      message = "Mod+Shift+V must stay unbound because direct insertion is unsafe";
    }
    {
      condition = !(builtins.hasAttr "Mod+M" binds);
      message = "Mod+M must not remain a Listener binding after Listener moves to Mod+V";
    }
    {
      condition = !(builtins.hasAttr "Mod+Ctrl+M" binds);
      message = "Mod+Ctrl+M must not remain a Listener binding after Listener moves to Mod+Ctrl+V";
    }
    {
      condition = !(builtins.hasAttr "Mod+Alt+M" binds);
      message = "Mod+Alt+M must not remain a Listener binding after Listener moves to Mod+Alt+V";
    }
    {
      condition = !(builtins.hasAttr "Mod+Alt+L" binds);
      message = "Mod+Alt+L must not remain a Listener binding";
    }
    {
      condition = !(builtins.hasAttr "Mod+Ctrl+Alt+M" binds);
      message = "Mod+Ctrl+Alt+M must not remain a Listener binding";
    }
    {
      condition = !(builtins.hasAttr "Mod+Shift+M" binds);
      message = "Mod+Shift+M must stay unbound";
    }
    {
      condition = !(builtins.elem "whisrs" packageNames);
      message = "dictation profile must not install Whisrs";
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
      condition = !(builtins.pathExists ../../packages/whisrs/default.nix);
      message = "packages/whisrs must not exist";
    }
    {
      condition = !(builtins.pathExists ../../packages/hyprvoice/default.nix);
      message = "packages/hyprvoice must not exist";
    }
    {
      condition = !(builtins.hasAttr "whisrs" moduleContent.systemd.user.services);
      message = "whisrs.service must not remain in the dictation profile";
    }
    {
      condition = !(builtins.hasAttr "whisrs-spool-retry" moduleContent.systemd.user.services);
      message = "whisrs-spool-retry.service must not remain in the dictation profile";
    }
    {
      condition = !(builtins.hasAttr "whisrs/config.toml" moduleContent.xdg.configFile);
      message = "Whisrs config must not remain managed by the dictation profile";
    }
    {
      condition =
        listenerService ? EnvironmentFile
        && listenerService.EnvironmentFile == "-%h/.config/listener/environment";
      message = "listener.service must keep the local environment override file";
    }
    {
      condition = listenerService ? UMask && listenerService.UMask == "0077";
      message = "listener.service must set UMask=0077 for private capture artifacts";
    }
    {
      condition = lib.versionAtLeast (listenerPackage.version or "0") "0.7.1";
      message = "Listener package must be version 0.7.1 or newer (ships private capture artifact hardening)";
    }
    {
      condition = !(lib.hasInfix "LISTENER_TRANSCRIPTION_PROGRAM" listenerEnvironmentExample);
      message = "listener environment example must not point production at an external transcriber";
    }
    {
      condition = lib.hasInfix "bluetooth.autoswitch-to-headset-profile = false" capturePolicy;
      message = "capture policy must prevent Bluetooth profile restore after capture streams stop";
    }
    {
      condition = lib.hasInfix "node.restore-default-targets = false" capturePolicy;
      message = "capture policy must select current inputs by priority rather than stale default-source state";
    }
    {
      condition = lib.hasInfix "device.name = \"bluez_card.04_A8_5A_0B_EB_B0\"" capturePolicy
        && lib.hasInfix "device.profile = \"headset-head-unit\"" capturePolicy
        && lib.hasInfix "session.dont-restore-off-profile = true" capturePolicy;
      message = "DJI profile policy must match its stable card identity and reject restored Off profiles";
    }
    {
      condition = lib.hasInfix "media.class = \"Audio/Source\"" capturePolicy
        && lib.hasInfix "node.name = \"~bluez_input.*\"" capturePolicy
        && lib.hasInfix "node.name = \"~alsa_input.usb-.*\"" capturePolicy
        && lib.hasInfix "priority.session = 2200" capturePolicy;
      message = "capture policy must prefer real Bluetooth and USB sources without admitting monitor or internal nodes";
    }
    {
      condition = lib.hasInfix "node.dont-fallback = true" keepalivePolicy
        && lib.hasInfix "node.linger = true" keepalivePolicy;
      message = "DJI keepalive must wait for its named source through profile replacement instead of falling back";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  let
    listenerToggleExecutable = builtins.elemAt (commandFor "Mod+V") 0;
    listenerCancelExecutable = builtins.elemAt (commandFor "Mod+Ctrl+V") 0;
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
    grep -F 'LISTENER_TRANSCRIPTION_CUSTOMIZATION_ARCHIVE=' ${listenerService.ExecStart} >/dev/null
    archive="$(${pkgs.gnused}/bin/sed -n 's/^export LISTENER_TRANSCRIPTION_CUSTOMIZATION_ARCHIVE="\(.*\/transcription-customization\.rkyv\)"$/\1/p' ${listenerService.ExecStart})"
    if [ -z "$archive" ] || [ ! -s "$archive" ]; then
      echo 'listener transcription customization archive must exist and be non-empty' >&2
      exit 1
    fi
    grep -F '/bin/listener cancel "$session"' ${listenerCancelExecutable} >/dev/null
    grep -F 'read_active_listener_session' ${listenerCancelExecutable} >/dev/null
    if grep -E '/bin/listener (stop|transcribe)|listener-openai-transcribe|wl-copy|LISTENER_CLIPBOARD_PROGRAM' ${listenerCancelExecutable} >/dev/null; then
      echo 'listener cancel wrapper must not stop/transcribe/copy' >&2
      exit 1
    fi
    printf 'listener dictation bindings checked\n' > "$out"
  ''
