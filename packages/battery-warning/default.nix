{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (packages: [ packages.dbus-next ]);
in
pkgs.writeShellScriptBin "battery-warning" ''
  exec ${python}/bin/python3 ${./controller.py} "$@"
''
