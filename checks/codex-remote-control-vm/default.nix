{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  codexCliPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  codexDesktopGate = pkgs.callPackage ../../owned-agents/codex/desktop-gate.nix {
    inherit codexCliPackage;
  };
  codexRemoteControlModule = ../../modules/home/profiles/min/agent-intercom.nix;
  corePackagesModule = ../../modules/home/core-packages.nix;
  testUser = "codex-remote-control-test";
  testHome = "/home/${testUser}";
  testUid = 1000;
  hmConfiguration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = {
          node.services = [ ];
          users.${testUser} = {
            name = testUser;
            size.min = true;
          };
        };
      };
      modules = [
        corePackagesModule
        codexRemoteControlModule
        {
          home = {
            username = testUser;
            homeDirectory = testHome;
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  service = hmConfiguration.systemd.user.services.codex-remote-control;
  socket = "${testHome}/.codex/app-server-control/app-server-control.sock";
in
assert service.Service.UMask == "0077";
assert service.Service.Restart == "always";
assert service.Service.WorkingDirectory == "/home/li/primary";
assert builtins.length service.Service.ExecStart == 1;
pkgs.testers.nixosTest {
  name = "codex-remote-control-vm";
  nodes.machine =
    { ... }:
    {
      users.groups.${testUser}.gid = testUid;
      systemd.tmpfiles.rules = [ "d /home/li/primary 0755 root root -" ];
      users.users.${testUser} = {
        isNormalUser = true;
        uid = testUid;
        group = testUser;
        home = testHome;
        createHome = true;
        linger = true;
      };

      environment.systemPackages = [
        pkgs.python3
        codexCliPackage
        codexDesktopGate
      ];
      environment.etc."codex-remote-control-initialize.py".source = ../codex-remote-control/initialize.py;

      systemd.user.services.codex-remote-control = {
        description = service.Unit.Description;
        wantedBy = service.Install.WantedBy;
        serviceConfig = service.Service;
      };
    };
  testScript = ''
    start_all()
    machine.wait_for_unit("user@${toString testUid}.service")
    machine.wait_until_succeeds("systemctl --user --machine=${testUser}@ is-active codex-remote-control.service")
    machine.succeed("systemctl --user --machine=${testUser}@ show codex-remote-control.service -p UMask --value | grep -x 0077")
    machine.wait_until_succeeds("test -S ${socket}")
    machine.succeed("test \"$(stat -c %a ${socket})\" = 600")
    machine.succeed("su -s /bin/sh -c 'CODEX_HOME=${testHome}/.codex codex app-server daemon version' ${testUser}")
    machine.succeed("su -s /bin/sh -c 'CODEX_HOME=${testHome}/.codex ${codexDesktopGate}/bin/codex app-server daemon version' ${testUser}")
    machine.wait_until_succeeds("python3 /etc/codex-remote-control-initialize.py ${socket} ${testHome}/.codex")
    machine.succeed("systemctl --user --machine=${testUser}@ is-active codex-remote-control.service")
    machine.succeed("test -S ${socket}")
    machine.succeed("systemctl --user --machine=${testUser}@ restart codex-remote-control.service")
    machine.wait_until_succeeds("systemctl --user --machine=${testUser}@ is-active codex-remote-control.service")
    machine.wait_until_succeeds("test -S ${socket}")
    machine.wait_until_succeeds("python3 /etc/codex-remote-control-initialize.py ${socket} ${testHome}/.codex")
  '';
}
