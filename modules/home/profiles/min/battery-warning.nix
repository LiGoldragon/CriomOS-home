{ config, lib, pkgs, horizon, ... }:
let
  cfg = config.criomosHome.batteryWarning;
  package = pkgs.callPackage ../../../../packages/battery-warning { };
  low = { on_battery = true; state = 2; warning_level = 3; percentage = 19.0; };
  charging = { on_battery = false; state = 1; warning_level = 1; percentage = 19.0; };
  recovered = { on_battery = true; state = 2; warning_level = 1; percentage = 21.0; };
  configuration = pkgs.writeText "battery-warning.json" (builtins.toJSON cfg.settings);
in
{
  options.criomosHome.batteryWarning = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = horizon.node.behavesAs.edge;
      description = "Present UPower warnings through the session notification owner and withdraw them when their cause ends.";
    };
    settings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = {
        app_name = "Battery";
        category = "device.battery";
        icon = "battery-caution";
        low_summary = "Battery low";
        critical_summary = "Battery critical";
        body = "Battery: {percentage:.0f}%";
        close_timeout_seconds = 5;
        proof_events = [
          { name = "low-before-charging"; state = low; expect = "posted"; }
          { name = "charging"; state = charging; expect = "withdrawn"; }
          { name = "low-before-recovery"; state = low; expect = "posted"; }
          { name = "threshold-recovered"; state = recovered; expect = "withdrawn"; }
        ];
      };
      description = "Notification text and receipt fixtures. Proof events never connect to UPower or change host policy.";
    };
    package = lib.mkOption { type = lib.types.package; readOnly = true; default = package; };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ package ];
    xdg.configFile."battery-warning/configuration.json".source = configuration;
    systemd.user.services.battery-warning = {
      Unit = {
        Description = "UPower battery warning lifecycle";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${package}/bin/battery-warning run ${configuration}";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
