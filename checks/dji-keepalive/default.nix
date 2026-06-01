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

  service = moduleContent.systemd.user.services.dji-keepalive;
  serviceScript = service.Service.ExecStart;

  assertions = [
    {
      condition = service.Service.Restart == "always";
      message = "dji-keepalive must restart after unexpected exits";
    }
    {
      condition = builtins.elem "graphical-session.target" service.Unit.PartOf;
      message = "dji-keepalive must stop with the graphical session";
    }
    {
      condition = builtins.elem "graphical-session.target" service.Install.WantedBy;
      message = "dji-keepalive must start with the graphical session";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "dji-keepalive-check" { } ''
    ${pkgs.gnugrep}/bin/grep -q 'public_source_name="bluez_input.$bluetooth_address"' ${serviceScript}
    ${pkgs.gnugrep}/bin/grep -q -- '--capture "$public_source_name"' ${serviceScript}
    ${pkgs.gnugrep}/bin/grep -q 'module-null-sink' ${serviceScript}
    ${pkgs.gnugrep}/bin/grep -q 'reasserting PipeWire profile without reconnecting Bluetooth' ${serviceScript}
    if ${pkgs.gnugrep}/bin/grep -q 'ConnectProfile' ${serviceScript}; then
      echo 'dji-keepalive must not hammer BlueZ ConnectProfile while PipeWire can set the headset profile' >&2
      exit 1
    fi
    if ${pkgs.gnugrep}/bin/grep -F -q 'left $headset_profile; reasserting profile" >&2' ${serviceScript}; then
      echo 'dji-keepalive must repair Bluetooth headset profile in-place instead of dropping the hot loopback stream' >&2
      exit 1
    fi
    if ${pkgs.gnugrep}/bin/grep -q 'ServicesResolved' ${serviceScript}; then
      echo 'dji-keepalive must not block on BlueZ ServicesResolved once PipeWire exposes the source' >&2
      exit 1
    fi
    printf 'dji keepalive checked\n' > "$out"
  ''
