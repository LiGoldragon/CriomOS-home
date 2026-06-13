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
  pipewirePath = "pipewire/pipewire.conf.d/60-dji-mic-hot-capture.conf";
  pipewirePolicy = moduleContent.xdg.configFile.${pipewirePath}.text;
  wireplumberPath = "wireplumber/wireplumber.conf.d/60-dji-mic-policy.conf";
  wireplumberPolicy = moduleContent.xdg.configFile.${wireplumberPath}.text;

  assertions = [
    {
      condition = !(builtins.hasAttr "dji-keepalive" services);
      message = "DJI mic profile stability must be owned by WirePlumber policy, not a polling keepalive service";
    }
    {
      condition = builtins.hasAttr pipewirePath moduleContent.xdg.configFile;
      message = "DJI mic must install a PipeWire graph configuration fragment";
    }
    {
      condition = builtins.hasAttr wireplumberPath moduleContent.xdg.configFile;
      message = "DJI mic policy must install a WirePlumber configuration fragment";
    }
    {
      condition = lib.hasInfix "libpipewire-module-loopback" pipewirePolicy;
      message = "DJI mic hot path must be a declarative PipeWire loopback module";
    }
    {
      condition = lib.hasInfix ''target.object = "bluez_input.04:A8:5A:0B:EB:B0"'' pipewirePolicy;
      message = "DJI mic loopback must capture from the public DJI source";
    }
    {
      condition = lib.hasInfix ''target.object = "dji_mic_hot_sink"'' pipewirePolicy;
      message = "DJI mic loopback must feed the dedicated hot sink";
    }
    {
      condition = lib.hasInfix "bluetooth.autoswitch-to-headset-profile = false" wireplumberPolicy;
      message = "DJI mic policy must disable WirePlumber's restore-to-off Bluetooth autoswitch path";
    }
    {
      condition = lib.hasInfix ''device.name = "bluez_card.04_A8_5A_0B_EB_B0"'' wireplumberPolicy;
      message = "DJI mic policy must match the DJI BlueZ card";
    }
    {
      condition = lib.hasInfix ''device.profile = "headset-head-unit"'' wireplumberPolicy;
      message = "DJI mic policy must pin the card to the headset/MSBC profile";
    }
    {
      condition = lib.hasInfix "node.pause-on-idle = false" wireplumberPolicy;
      message = "DJI mic nodes must not pause on idle";
    }
    {
      condition = lib.hasInfix "session.suspend-timeout-seconds = 0" wireplumberPolicy;
      message = "DJI mic nodes must disable session idle suspension";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "dji-wireplumber-policy-check" { } ''
    if ${pkgs.gnugrep}/bin/grep -R -q 'dji-keepalive' ${../../modules/home/profiles/min/dictation.nix}; then
      echo 'dictation module must not contain the removed polling dji-keepalive service' >&2
      exit 1
    fi
    printf 'dji wireplumber policy checked\n' > "$out"
  ''
