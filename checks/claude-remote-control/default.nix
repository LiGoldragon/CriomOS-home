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
    name = "li";
    size.min = true;
  };
  secondUser = {
    name = "claude-remote-control-second";
    size.min = true;
  };
  unsetConfiguration = mkConfiguration primaryUser { };
  secondConfiguration = mkConfiguration secondUser { };
  homeRootConfiguration = mkConfiguration primaryUser {
    criomos.claudeRemoteControl.workingDirectory = "/home/li";
  };
  ownerConfiguration = mkConfiguration primaryUser {
    criomos.claudeRemoteControl = {
      workingDirectory = "/srv/claude-remote-control-owner";
      spawn = "same-dir";
    };
  };
  service = ownerConfiguration.systemd.user.services.claude-remote-control;
  primaryTrustActivation = unsetConfiguration.home.activation.mergeAgentIntercomClaudeMcp;
  primaryTrustCanonicalization = unsetConfiguration.home.activation.canonicalizeClaudeWorkspaceTrust;
  secondTrustActivation = secondConfiguration.home.activation.mergeAgentIntercomClaudeMcp;
  secondTrustCanonicalization = secondConfiguration.home.activation.canonicalizeClaudeWorkspaceTrust;
in
assert unsetConfiguration.systemd.user.services ? claude-remote-control;
assert
  unsetConfiguration.systemd.user.services.claude-remote-control.Service.WorkingDirectory
  == "/home/li/primary";
assert
  secondConfiguration.systemd.user.services.claude-remote-control.Service.WorkingDirectory
  == "/home/claude-remote-control-second/primary";
assert unsetConfiguration.home.activation ? mergeAgentIntercomClaudeMcp;
assert unsetConfiguration.home.activation ? canonicalizeClaudeWorkspaceTrust;
assert secondConfiguration.home.activation ? mergeAgentIntercomClaudeMcp;
assert secondConfiguration.home.activation ? canonicalizeClaudeWorkspaceTrust;
assert !(builtins.tryEval homeRootConfiguration.home.activationPackage).success;
assert ownerConfiguration.systemd.user.services ? claude-remote-control;
assert service.Service.WorkingDirectory == "/srv/claude-remote-control-owner";
assert service.Service.Restart == "always";
assert service.Service.UMask == "0077";
pkgs.runCommand "claude-remote-control-contract" { } ''
  set -eu
  owner_exec='${builtins.head service.Service.ExecStart}'
  test "$owner_exec" = '${fixtureClaude}/bin/claude remote-control --spawn=same-dir --permission-mode bypassPermissions'
  working_directory="$TMPDIR/working-directory"
  mkdir -p "$working_directory"
  test "$(cd "$working_directory" && ${fixtureClaude}/bin/claude remote-control --spawn=same-dir --permission-mode bypassPermissions)" \
    = "$working_directory"$'\nremote-control\n--spawn=same-dir\n--permission-mode\nbypassPermissions'
  primary_home="$TMPDIR/primary-home"
  second_home="$TMPDIR/second-home"
  mkdir -p "$primary_home" "$second_home"
  printf '%s' '{"preserved":{"value":"kept"},"projects":{"/existing/workspace":false,"/home/li/primary":true}}' > "$primary_home/.claude.json"
  printf '%s' '{"preserved":{"value":"second-kept"},"projects":{"/existing/workspace":false,"/home/claude-remote-control-second/primary":{"hasTrustDialogAccepted":false,"preservedProject":"second-kept"}}}' > "$second_home/.claude.json"
  DRY_RUN_CMD=
  run() { "$@"; }
  export HOME="$primary_home"
  primary_metadata="$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' "$primary_home/.claude.json")"
  scalar_failure_log="$TMPDIR/scalar-project-hexis.log"
  set +e
  ( ${primaryTrustActivation.data} ) >"$scalar_failure_log" 2>&1
  scalar_failure_status=$?
  set -e
  test "$scalar_failure_status" -ne 0
  ${pkgs.gnugrep}/bin/grep -F \
    'hexis: cannot apply at pointer /projects/~1home~1li~1primary/hasTrustDialogAccepted: parent at segment "hasTrustDialogAccepted" is not an object' \
    "$scalar_failure_log"
  ( ${primaryTrustCanonicalization.data} )
  ${pkgs.coreutils}/bin/cp "$primary_home/.claude.json" "$primary_home/canonicalized.json"
  ( ${primaryTrustCanonicalization.data} )
  ${pkgs.diffutils}/bin/cmp "$primary_home/canonicalized.json" "$primary_home/.claude.json"
  test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' "$primary_home/.claude.json")" = "$primary_metadata"
  ( ${primaryTrustActivation.data} )
  ${pkgs.jq}/bin/jq -e '
    .preserved.value == "kept"
    and .projects["/existing/workspace"] == false
    and (.projects["/home/li/primary"] | type) == "object"
    and .projects["/home/li/primary"].hasTrustDialogAccepted == true
  ' "$primary_home/.claude.json"
  export HOME="$second_home"
  second_metadata="$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' "$second_home/.claude.json")"
  ${pkgs.coreutils}/bin/cp "$second_home/.claude.json" "$second_home/before-canonicalization.json"
  ( ${secondTrustCanonicalization.data} )
  ${pkgs.diffutils}/bin/cmp "$second_home/before-canonicalization.json" "$second_home/.claude.json"
  test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' "$second_home/.claude.json")" = "$second_metadata"
  ( ${secondTrustActivation.data} )
  ${pkgs.jq}/bin/jq -e '
    .preserved.value == "second-kept"
    and .projects["/existing/workspace"] == false
    and .projects["/home/claude-remote-control-second/primary"].hasTrustDialogAccepted == true
    and .projects["/home/claude-remote-control-second/primary"].preservedProject == "second-kept"
  ' "$second_home/.claude.json"
  touch "$out"
''
