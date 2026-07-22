{
  config,
  lib,
  pkgs,
  user,
  horizon,
  ...
}:
let
  inherit (horizon.node) behavesAs;
  inherit (user) size;
  helperPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.dbus-next ]);
  activeNetworkHelper = pkgs.writeShellApplication {
    name = "criomos-active-network-helper";
    runtimeInputs = [ pkgs.iw ];
    text = ''
      exec ${helperPython}/bin/python ${./noctalia-plugins/active-network/active_network_helper.py} \
        --iw ${pkgs.iw}/bin/iw "$@"
    '';
  };
in
lib.mkIf (size.min && behavesAs.edge) {
  home.packages = [ activeNetworkHelper ];

  systemd.user.services.active-network-widget = {
    Unit = {
      Description = "NetworkManager event helper for the Active Network Noctalia widget";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    Service = {
      RuntimeDirectory = "active-network";
      RuntimeDirectoryMode = "0700";
      ExecStart = "${activeNetworkHelper}/bin/criomos-active-network-helper --socket %t/active-network/status.sock";
      Restart = "on-failure";
      RestartSec = "2s";
      UMask = "0077";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
