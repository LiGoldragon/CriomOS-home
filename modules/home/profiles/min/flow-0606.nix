# The Flow writer at main. Home gives the opened store one owner and the
# writer brings its matching clients and hook. See the stopped-store guard.
{ config, lib, ... }:
let
  cohort = import ../../../../lib/flow-0607-cohort.nix;
in
{
  imports = [
    (import ./flow-handoff.nix (cohort // {
      action = "restore";
      selected = cohort.departure;
    }))
    (import ./flow-nexus-place.nix {
      version = "0.60.6";
      slug = "0606";
    })
  ];

  criomosHome.flow0606 = {
    place = "main";
    stableHook = true;
    glibcAllocator = {
      arenaMaximum = 2;
      mmapThreshold = 1048576;
      trimThreshold = 131072;
    };
    # The Nexus at main is held to 3G of memory and no swap, so the kernel
    # stops a runaway Nexus at that size.
    memoryLimit = {
      maximum = "3G";
      swapMaximum = "0";
    };
  };

  systemd.user.services.${config.criomosHome.flow0606.unit}.Unit.X-SwitchMethod = "keep-old";

  home.packages = [ config.criomosHome.flow0606.clients ];

  home.file.".local/bin/flow".source = "${config.criomosHome.flow0606.package}/bin/flow";
  home.file.".local/bin/flow-meta".source = "${config.criomosHome.flow0606.package}/bin/flow-meta";

  xdg.configFile."nexus/flow-nexus.datom" = lib.mkIf (config.criomosHome.flow0606.place == "main") {
    source = "${config.criomosHome.flow0606.placeConfiguration}/nexus/flow-nexus.datom";
  };
}
