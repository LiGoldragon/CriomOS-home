{ inputs, pkgs, ... }:
let
  fixtureClaude = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      printf '%s\n' "$PWD" "$@"
    '';
  };
  mkConfiguration =
    overrides:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs.user = {
        size.min = true;
      };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/claude-remote-control.nix
        {
          home = {
            username = "claude-remote-control-test";
            homeDirectory = "/home/claude-remote-control-test";
            stateVersion = "26.05";
          };
          criomos.corePackages.claude = fixtureClaude;
        }
        overrides
      ];
    }).config;
  unsetConfiguration = mkConfiguration { };
  homeRootConfiguration = mkConfiguration {
    criomos.claudeRemoteControl.workingDirectory = "/home/claude-remote-control-test";
  };
  ownerConfiguration = mkConfiguration {
    criomos.claudeRemoteControl = {
      workingDirectory = "/srv/claude-remote-control-owner";
      spawn = "same-dir";
    };
  };
  service = ownerConfiguration.systemd.user.services.claude-remote-control;
in
assert !(builtins.tryEval unsetConfiguration.home.activationPackage).success;
assert !(builtins.tryEval homeRootConfiguration.home.activationPackage).success;
assert ownerConfiguration.systemd.user.services ? claude-remote-control;
assert service.Service.WorkingDirectory == "/srv/claude-remote-control-owner";
assert service.Service.Restart == "always";
assert service.Service.UMask == "0077";
pkgs.runCommand "claude-remote-control-contract" { } ''
  set -eu
  owner_exec='${builtins.head service.Service.ExecStart}'
  test "$owner_exec" = '${fixtureClaude}/bin/claude remote-control --spawn=same-dir'
  working_directory="$TMPDIR/working-directory"
  mkdir -p "$working_directory"
  test "$(cd "$working_directory" && ${fixtureClaude}/bin/claude remote-control --spawn=same-dir)" \
    = "$working_directory"$'\nremote-control\n--spawn=same-dir'
  touch "$out"
''
