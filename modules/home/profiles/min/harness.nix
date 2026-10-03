{
  config,
  lib,
  pkgs,
  ...
}:
let
  # One immutable Harness revision serves the user daemon and every client:
  # the same package Home already installs for flow-id.
  harnessPackage = config.criomos.corePackages.flowId;

  # A caller-set HARNESS_SOCKET / HARNESS_META_SOCKET is honoured, so a
  # sandboxed or relocated daemon can be addressed through the installed
  # clients; otherwise the sockets resolve under the service's runtime
  # directory. The wrappers shadow the package's raw clients on PATH.
  harnessClients =
    pkgs.runCommand "${harnessPackage.name}-clients" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        for client in harness harness-usage; do
          makeWrapper ${harnessPackage}/bin/$client $out/bin/$client \
            --run 'export HARNESS_SOCKET="''${HARNESS_SOCKET:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/harness/harness.sock}"'
        done
        makeWrapper ${harnessPackage}/bin/meta-harness $out/bin/meta-harness \
          --run 'export HARNESS_META_SOCKET="''${HARNESS_META_SOCKET:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/harness/meta-harness.sock}"'
      '';
in
{
  home.packages = [ (lib.hiPrio harnessClients) ];

  # The user's own Harness daemon. harness-daemon-launch writes the typed
  # startup record for this unit's runtime directory and the user's uid
  # (owner-only ordinary, meta and supervision sockets; no harness instance)
  # and becomes harness-daemon. It serves one-call reads such as the usage
  # snapshot; it keeps no store and runs no timer.
  systemd.user.services.harness-daemon = {
    Unit = {
      Description = "Harness daemon: one-call usage snapshot and harness surfaces";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };

    Service = {
      RuntimeDirectory = "harness";
      RuntimeDirectoryMode = "0700";
      ExecStart = "${harnessPackage}/bin/harness-daemon-launch";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
