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
  defaultConfiguration = mkConfiguration { };
  service = defaultConfiguration.systemd.user.services.claude-remote-control;
  customConfiguration = mkConfiguration {
    criomos.claudeRemoteControl = {
      workingDirectory = "/var/lib/claude-worktree";
      spawn = "worktree";
    };
  };
  customService = customConfiguration.systemd.user.services.claude-remote-control;
in
assert defaultConfiguration.systemd.user.services ? claude-remote-control;
assert service.Service.WorkingDirectory == "/home/claude-remote-control-test";
assert service.Service.Restart == "always";
assert service.Service.UMask == "0077";
assert customService.Service.WorkingDirectory == "/var/lib/claude-worktree";
pkgs.runCommand "claude-remote-control-contract" { } ''
  set -eu
  default_exec='${builtins.head service.Service.ExecStart}'
  custom_exec='${builtins.head customService.Service.ExecStart}'
  test "$default_exec" = '${fixtureClaude}/bin/claude remote-control --spawn=same-dir'
  test "$custom_exec" = '${fixtureClaude}/bin/claude remote-control --spawn=worktree'
  working_directory="$TMPDIR/working-directory"
  mkdir -p "$working_directory"
  test "$(cd "$working_directory" && ${fixtureClaude}/bin/claude remote-control --spawn=same-dir)" \
    = "$working_directory"$'\nremote-control\n--spawn=same-dir'
  touch "$out"
''
