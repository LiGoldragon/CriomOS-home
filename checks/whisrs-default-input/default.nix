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
      message = "Dictation must not install DJI-specific Bluetooth policy in the ordinary profile";
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
