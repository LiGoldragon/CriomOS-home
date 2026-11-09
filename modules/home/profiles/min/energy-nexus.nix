# The Energy Nexus at its place (vision:nexus-v1, "A Nexus starts in its
# place"; vision:energy-nexus-v1). Its two processes are two units, each
# started with the place's name and its two directories:
# - energy-nexus, the daemon: energy.sock and energy-meta.sock in
#   $XDG_RUNTIME_DIR/nexus/<place>/, its memory energy.rkyv in
#   $XDG_STATE_HOME/nexus/<place>/.
# - energy-translator, the translator, its own process: energy-translator.sock,
#   energy-meta-translator.sock and energy-emission.sock, its memory
#   energy-translator.rkyv.
# Each process sends READY=1 once its sockets listen, so each unit is
# Type=notify. Energy reads a provider on events, never on an interval; one
# of them is a turn ending, from the Flow Nexus at the same place, which the
# daemon subscribes to through the translator. So the order is Flow, then
# the translator, then the daemon:
# - the translator wants Flow's unit and is ordered after it, and is not
#   bound to it: Energy keeps running when Flow stops, and the translator
#   subscribes again when Flow's socket is moved to its name at the place
#   (inotify IN_MOVED_TO, which Flow does only once the socket listens;
#   never a timer), as Curriculum is wanted by Flow and reconnected to when
#   it returns;
# - the daemon is ordered after the translator, bound to it and wanted by
#   it: it starts once the translator serves, and holds Flow's turn ends
#   open through it across Flow going and coming back. The first opening
#   is the daemon's first reading.
#
# The place is shared with every other Nexus at it and declared by
# nexus-places.nix, so neither unit names a RuntimeDirectory or
# StateDirectory, and both are ordered after the unit that makes the place.
# The Energy processes never make the place: one whose place is absent does
# not start. Stopped, each removes its own sockets and nothing else.
#
# The clients are on PATH: energy-nexus, energy-nexus-meta and energy-pace,
# each `<client> <place> '<query>'`. Energy's configuration (thresholds, the
# Flow and Codex programs, reminders, targets) is state in its memory, set
# through energy-nexus-meta.
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
  flow = lib.optional (cfg.flowUnit != null) "${cfg.flowUnit}.service";
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
      description = "The translator's unit; the daemon's is bound to it.";
    };
    flowUnit = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        let
          flow0533 = config.criomosHome.flow0533;
        in
        if flow0533.enable && flow0533.place == cfg.place then flow0533.unit else null;
      defaultText = lib.literalExpression "the Flow 0.53.3 unit, when it is enabled at this place";
      description = "The unit of the Flow Nexus at this place, whose turn ends Energy reads on: the translator wants it and is ordered after it, and keeps running when it stops. Null when no Flow runs at the place.";
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
    systemd.user.services.${cfg.translatorUnit} = {
      Unit = {
        Description = "Energy Nexus translator at ${cfg.place}";
        After = [ places.unit ] ++ flow;
        Wants = flow;
      };
      Service = service "energy-translator";
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Energy Nexus daemon at ${cfg.place}";
        After = [
          places.unit
          "${cfg.translatorUnit}.service"
        ];
        BindsTo = [ "${cfg.translatorUnit}.service" ];
      };
      Service = service "energy-nexus-daemon";
      Install.WantedBy = [
        "default.target"
        "${cfg.translatorUnit}.service"
      ];
    };
  };
}
