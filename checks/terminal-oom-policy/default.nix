# A terminal scope survives the kernel OOM kill of one of its processes.
#
# The generated `app-ghostty-.scope.d` drop-in is installed for a lingering
# user in a VM; a scope named like a Ghostty surface scope is started under a
# small memory limit with a long-lived process (the harness) and a process
# that overruns the limit (the test binary). The kernel kills the overrunning
# process; the scope, and the harness in it, must still be running. A scope
# outside the prefix and the user manager's default keep `stop`.
{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  terminalScopesModule = ../../modules/home/profiles/min/terminal-scopes.nix;
  testUser = "terminal-oom-check";
  testHome = "/home/${testUser}";
  testUid = 1000;
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      terminalScopesModule
      {
        home = {
          username = testUser;
          homeDirectory = testHome;
          stateVersion = "26.05";
        };
      }
    ];
  };
  dropIn =
    homeConfiguration.config.xdg.configFile."systemd/user/app-ghostty-.scope.d/oom-policy.conf".source;
  dropInDirectory = "${testHome}/.config/systemd/user/app-ghostty-.scope.d";
  surfaceScope = "app-ghostty-surface-transient-4242";
  controlScope = "app-control-4242";
  asUser =
    command: "su -s /bin/sh -c 'XDG_RUNTIME_DIR=/run/user/${toString testUid} ${command}' ${testUser}";
  showScope = scope: property: asUser "systemctl --user show ${scope}.scope -p ${property} --value";
  # Run inside the scope: the harness stays (its stdio detached, so the
  # session's pipe closes when the shell leaves); the overrunning process is
  # killed by the kernel; the shell reports the kill and leaves.
  surfaceSession = pkgs.writeShellScript "terminal-oom-surface-session" ''
    sleep 600 </dev/null >/dev/null 2>&1 &
    ${pkgs.python3}/bin/python3 -c 'bytearray(256 * 1024 * 1024)'
    echo "overrun:$?"
  '';
  startSurface = asUser (
    lib.concatStringsSep " " [
      "systemd-run --user --scope --collect --quiet"
      "-p MemoryMax=64M -p MemorySwapMax=0"
      "--unit=${surfaceScope}"
      "${surfaceSession}"
    ]
  );
  startControl = asUser (
    lib.concatStringsSep " " [
      "systemd-run --user --scope --collect --quiet"
      "--unit=${controlScope}"
      "systemctl --user show ${controlScope}.scope -p OOMPolicy --value"
    ]
  );
in
pkgs.testers.nixosTest {
  name = "terminal-oom-policy";
  nodes.machine =
    { lib, ... }:
    {
      # The test profile panics the kernel on any OOM so that a starved VM
      # fails fast; here the OOM kill inside the scope is the event under test.
      boot.kernel.sysctl."vm.panic_on_oom" = lib.mkForce 0;

      users.users.${testUser} = {
        isNormalUser = true;
        uid = testUid;
        home = testHome;
        createHome = true;
        linger = true;
      };
      systemd.tmpfiles.rules = [
        "d ${testHome}/.config 0755 ${testUser} users -"
        "d ${testHome}/.config/systemd 0755 ${testUser} users -"
        "d ${testHome}/.config/systemd/user 0755 ${testUser} users -"
        "d ${dropInDirectory} 0755 ${testUser} users -"
        "L+ ${dropInDirectory}/oom-policy.conf - - - - ${dropIn}"
      ];
    };
  testScript = ''
    start_all()
    machine.wait_for_unit("user@${toString testUid}.service")
    machine.succeed("${asUser "systemctl --user show -p DefaultOOMPolicy --value"} | grep -x stop")

    machine.succeed("${startSurface} | grep -x overrun:137")
    machine.succeed("${showScope surfaceScope "OOMPolicy"} | grep -x continue")
    machine.succeed("${showScope surfaceScope "ActiveState"} | grep -x active")
    machine.succeed("${showScope surfaceScope "Result"} | grep -x success")
    control_group = machine.succeed("${showScope surfaceScope "ControlGroup"}").strip()
    machine.succeed(f"grep -qx sleep /proc/$(head -n1 /sys/fs/cgroup{control_group}/cgroup.procs)/comm")

    machine.succeed("${startControl} | grep -x stop")
  '';
}
