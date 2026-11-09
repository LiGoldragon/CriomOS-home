# The places Nexuses run at (vision:nexus-v1, "A Nexus starts in its place").
# A place is two directories: Runtime, $XDG_RUNTIME_DIR/nexus/<place>/, for
# sockets, and State, $XDG_STATE_HOME/nexus/<place>/ (~/.local/state/nexus/
# <place>/), for memory. Every Nexus at a place shares them and none owns
# them: each makes and removes only its own sockets and files inside.
#
# They are declared once, here, as systemd user tmpfiles rules (`d`, mode
# 0700, no age, so nothing in them is ever cleaned), in their own file
# under ~/.config/user-tmpfiles.d, read by the host's own user unit:
# - A unit's RuntimeDirectory= or StateDirectory= belongs to that unit, and
#   stopping it removes the runtime directory with every other Nexus's
#   sockets in it.
# - Runtime is a tmpfs emptied at logout and reboot; a Home activation step
#   runs only at a switch. systemd-tmpfiles-setup.service runs at every start
#   of the user manager, before basic.target, so the places exist before any
#   Nexus unit starts. When the rules change, activation applies this file
#   at once, naming the user's runtime root, since a Lojix activation runs
#   without XDG_RUNTIME_DIR.
# - %t and %S are the user manager's own XDG roots, so no uid or path is
#   written here.
# - Home Manager's systemd.user.tmpfiles is not used: it installs its own
#   copy of systemd-tmpfiles-clean.timer, which the host masks, so every
#   switch failed starting it; and it applies the rules by running
#   systemd-tmpfiles in the activation's environment, where a Lojix
#   activation has no XDG_RUNTIME_DIR and every %t rule is skipped.
#
# The places are configuration: the list below, never one per Nexus. Each
# Nexus unit orders itself after `unit` and asserts its place is listed.
{
  config,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.nexusPlaces;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  directory = path: "d ${path} 0700 - - -";
  roots = [
    "%t/nexus"
    "%S/nexus"
  ];
  place = name: [
    "%t/nexus/${name}"
    "%S/nexus/${name}"
  ];
in
{
  options.criomosHome.nexusPlaces = {
    places = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-z][a-z0-9-]*");
      default = [ "main" ];
      description = "The places Nexuses run at: main, the stable one, and next while a candidate runs there.";
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "systemd-tmpfiles-setup.service";
      description = "The user unit that makes the place directories; every Nexus unit is ordered after it.";
    };
  };

  config = lib.mkIf (sizeAtLeast "Min" && cfg.places != [ ]) {
    xdg.configFile."user-tmpfiles.d/nexus-places.conf" = {
      text = lib.concatMapStrings (path: directory path + "\n") (roots ++ lib.concatMap place cfg.places);
      onChange = ''
        run env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
          ${pkgs.systemd}/bin/systemd-tmpfiles --user --create "${config.xdg.configHome}/user-tmpfiles.d/nexus-places.conf"
      '';
    };
  };
}
