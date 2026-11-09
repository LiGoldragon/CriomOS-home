# The Energy Nexus at its place (vision:nexus-v1, "A Nexus starts in its
# place"; vision:energy-nexus-v1). energy-nexus-poc runs its two processes,
# the daemon and the translator, each started with the place's name and its
# two directories: sockets in $XDG_RUNTIME_DIR/nexus/<place>/ (energy.sock,
# energy-meta.sock, energy-translator.sock, energy-meta-translator.sock,
# energy-emission.sock), memory in $XDG_STATE_HOME/nexus/<place>/
# (energy.rkyv, energy-translator.rkyv).
#
# The place is shared with every other Nexus at it and declared by
# nexus-places.nix, so the unit names no RuntimeDirectory or StateDirectory
# and is ordered after the unit that makes the place. The Energy processes
# never make the place: one whose place is absent does not start. Stopped,
# each removes its own sockets and nothing else.
#
# Energy's configuration (polling minutes, the Flow and Codex programs,
# reminders, targets) is state in its memory, set through energy-nexus-meta.
{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.energyNexus;
  places = config.criomosHome.nexusPlaces;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  package = inputs.energy-nexus.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.criomosHome.energyNexus = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.elem "AgentStack" user.capabilities;
    };
    place = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "The place the Energy Nexus runs at; one of criomosHome.nexusPlaces.places.";
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "energy-nexus";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
    };
  };

  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = builtins.elem cfg.place places.places;
        message = "criomosHome.energyNexus.place ${cfg.place} is not one of criomosHome.nexusPlaces.places.";
      }
    ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Energy Nexus at ${cfg.place}";
        After = [ places.unit ];
      };
      Service = {
        Type = "exec";
        UMask = "0077";
        ExecStart = "${package}/bin/energy-nexus-poc ${cfg.place} %t/nexus/${cfg.place} %S/nexus/${cfg.place}";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
