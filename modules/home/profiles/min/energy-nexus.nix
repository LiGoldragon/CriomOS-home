# The Energy Nexus at its place (vision:nexus-v1, "A Nexus starts in its
# place"; vision:energy-nexus-v1). Its two processes are two units, each
# started with the place's name and its two directories:
# - energy-nexus, the daemon: energy.sock and energy-meta.sock in
#   $XDG_RUNTIME_DIR/nexus/<place>/, its memory energy.rkyv in
#   $XDG_STATE_HOME/nexus/<place>/.
# - energy-translator, the translator, its own process: energy-translator.sock,
#   energy-meta-translator.sock and energy-emission.sock, its memory
#   energy-translator.rkyv. It is ordered after the daemon and bound to it,
#   and wanted by it, so it starts, stops and restarts with the daemon.
# Each process sends READY=1 once its sockets listen, so each unit is
# Type=notify: the translator starts once the daemon serves.
#
# The place is shared with every other Nexus at it and declared by
# nexus-places.nix, so neither unit names a RuntimeDirectory or
# StateDirectory, and both are ordered after the unit that makes the place.
# The Energy processes never make the place: one whose place is absent does
# not start. Stopped, each removes its own sockets and nothing else.
#
# The clients are on PATH: energy-nexus, energy-nexus-meta and energy-pace,
# each `<client> <place> '<query>'`. Energy's configuration (polling
# minutes, the Flow and Codex programs, reminders, targets) is state in its
# memory, set through energy-nexus-meta.
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
  # The place's name and its two directories, as each process takes them.
  placeArguments = "${cfg.place} %t/nexus/${cfg.place} %S/nexus/${cfg.place}";
  # The commands a person runs; the daemon and the translator run only as
  # the units below.
  clients = pkgs.runCommand "energy-nexus-clients" { } ''
    mkdir -p $out/bin
    for client in energy-nexus energy-nexus-meta energy-pace; do
      ln -s ${package}/bin/$client $out/bin/$client
    done
  '';
  service = binary: {
    Type = "notify";
    UMask = "0077";
    ExecStart = "${package}/bin/${binary} ${placeArguments}";
    Restart = "on-failure";
    RestartSec = "2s";
  };
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
      description = "The daemon's unit.";
    };
    translatorUnit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "energy-translator";
      description = "The translator's unit, bound to the daemon's.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
    };
    clients = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = clients;
      description = "energy-nexus, energy-nexus-meta and energy-pace, on PATH.";
    };
  };

  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = builtins.elem cfg.place places.places;
        message = "criomosHome.energyNexus.place ${cfg.place} is not one of criomosHome.nexusPlaces.places.";
      }
    ];
    home.packages = [ clients ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Energy Nexus daemon at ${cfg.place}";
        After = [ places.unit ];
      };
      Service = service "energy-nexus-daemon";
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.${cfg.translatorUnit} = {
      Unit = {
        Description = "Energy Nexus translator at ${cfg.place}";
        After = [
          places.unit
          "${cfg.unit}.service"
        ];
        BindsTo = [ "${cfg.unit}.service" ];
      };
      Service = service "energy-translator";
      Install.WantedBy = [ "${cfg.unit}.service" ];
    };
  };
}
