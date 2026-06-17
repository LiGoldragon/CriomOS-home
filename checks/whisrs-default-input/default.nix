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
  services = moduleContent.systemd.user.services or { };
  whisrsService = services.whisrs;
  dictationModuleSource = builtins.readFile ../../modules/home/profiles/min/dictation.nix;

  assertions = [
    {
      condition = !(lib.hasInfix "PIPEWIRE_NODE" dictationModuleSource);
      message = "Whisrs must not hard-bind capture to a removable PipeWire source";
    }
    {
      condition =
        !(builtins.hasAttr "pipewire/pipewire.conf.d/60-dji-mic-hot-capture.conf" moduleContent.xdg.configFile);
      message = "Dictation must not create an always-present DJI hot virtual source";
    }
    {
      condition =
        !(builtins.hasAttr "wireplumber/wireplumber.conf.d/60-dji-mic-policy.conf" moduleContent.xdg.configFile);
      message = "Dictation must not install the old DJI Bluetooth hot-loop policy";
    }
    {
      condition = builtins.hasAttr "wireplumber/wireplumber.conf.d/60-dji-source-priority.conf" moduleContent.xdg.configFile;
      message = "Dictation must install the DJI source priority policy";
    }
    {
      condition = !(lib.hasInfix "criomos-whisrs" dictationModuleSource);
      message = "Dictation must not prefer DJI through a Whisrs-specific wrapper";
    }
    {
      condition = lib.hasInfix "bluez_input.04:A8:5A:0B:EB:B0" dictationModuleSource;
      message = "The DJI preference must target the raw DJI Bluetooth source";
    }
    {
      condition = lib.hasInfix "priority.session = 3000" dictationModuleSource;
      message = "The DJI preference must use system audio source priority";
    }
    {
      condition = !(lib.hasInfix "set-default-source" dictationModuleSource);
      message = "Dictation must not change the default source in a Whisrs-specific wrapper";
    }
    {
      condition = lib.elem "pipewire.service" whisrsService.Unit.After;
      message = "Whisrs must still start after PipeWire";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "whisrs-default-input-check" { } ''
    printf 'whisrs default input policy checked\n' > "$out"
  ''
