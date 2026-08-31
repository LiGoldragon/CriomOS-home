{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixtureClaude = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      printf '%s\n' "$PWD" "$@"
    '';
  };
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
  mkConfiguration =
    user: overrides:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs user;
        hexis = inputs.hexis.packages.${system}.default;
        horizon = {
          node.services = [ ];
          users.${user.name} = user;
        };
      };
      modules = [
        ../../modules/home/core-packages.nix
        agentIntercomModule
        ../../modules/home/profiles/min/claude-remote-control.nix
        {
          home = {
            username = user.name;
            homeDirectory = "/home/${user.name}";
            stateVersion = "26.05";
          };
          criomos.corePackages.claude = fixtureClaude;
        }
        overrides
      ];
    }).config;
  primaryUser = {
    name = "claude-remote-control-test";
    size.min = true;
  };
  secondUser = {
    name = "claude-remote-control-second";
    size.min = true;
  };
  unsetConfiguration = mkConfiguration primaryUser { };
  secondConfiguration = mkConfiguration secondUser { };
  homeRootConfiguration = mkConfiguration primaryUser {
    criomos.claudeRemoteControl.workingDirectory = "/home/claude-remote-control-test";
  };
  ownerConfiguration = mkConfiguration primaryUser {
    criomos.claudeRemoteControl = {
      workingDirectory = "/srv/claude-remote-control-owner";
      spawn = "same-dir";
    };
  };
  service = ownerConfiguration.systemd.user.services.claude-remote-control;
  primaryTrustActivation = unsetConfiguration.home.activation.mergeAgentIntercomClaudeMcp;
  secondTrustActivation = secondConfiguration.home.activation.mergeAgentIntercomClaudeMcp;
in
assert unsetConfiguration.systemd.user.services ? claude-remote-control;
assert
  unsetConfiguration.systemd.user.services.claude-remote-control.Service.WorkingDirectory
  == "/home/claude-remote-control-test/primary";
assert
  secondConfiguration.systemd.user.services.claude-remote-control.Service.WorkingDirectory
  == "/home/claude-remote-control-second/primary";
assert unsetConfiguration.home.activation ? mergeAgentIntercomClaudeMcp;
assert secondConfiguration.home.activation ? mergeAgentIntercomClaudeMcp;
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
  primary_home="$TMPDIR/primary-home"
  second_home="$TMPDIR/second-home"
  mkdir -p "$primary_home" "$second_home"
  printf '%s' '{"preserved":{"value":"kept"},"projects":{"/existing/workspace":false}}' > "$primary_home/.claude.json"
  printf '%s' '{"preserved":{"value":"second-kept"},"projects":{"/existing/workspace":false}}' > "$second_home/.claude.json"
  DRY_RUN_CMD=
  run() { "$@"; }
  export HOME="$primary_home"
  ${primaryTrustActivation.data}
  ${pkgs.jq}/bin/jq -e '
    .preserved.value == "kept"
    and .projects["/existing/workspace"] == false
    and .projects["/home/claude-remote-control-test/primary"] == true
  ' "$primary_home/.claude.json"
  export HOME="$second_home"
  ${secondTrustActivation.data}
  ${pkgs.jq}/bin/jq -e '
    .preserved.value == "second-kept"
    and .projects["/existing/workspace"] == false
    and .projects["/home/claude-remote-control-second/primary"] == true
  ' "$second_home/.claude.json"
  touch "$out"
''
