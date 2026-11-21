{ pkgs, ... }:
let
  python = pkgs.python3.withPackages (packages: [ packages.dbus-next ]);
  package = pkgs.callPackage ../../packages/battery-warning { };
  profile = builtins.readFile ../../modules/home/profiles/min/sfwbar.nix;
in
assert pkgs.lib.hasInfix "enable_daemon = false;" profile;
assert pkgs.lib.hasInfix ''match_content = ".*";'' profile;
assert pkgs.lib.hasInfix "show_toast = false;" profile;
assert pkgs.lib.hasInfix "default-timeout = 3000;" profile;
assert pkgs.lib.hasInfix "default-timeout = 10000;" profile;
pkgs.runCommand "battery-warning-causal-withdrawal" {
  nativeBuildInputs = [ python pkgs.dbus ];
} ''
  ${package}/bin/battery-warning --help >/dev/null
  python3 ${./test.py} ${../../packages/battery-warning/controller.py}
  touch "$out"
''
