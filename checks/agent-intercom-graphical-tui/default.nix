{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  horizon = {
    node = {
      name = "graphical-tui-contract";
      services = [
        { AgentIntercomLocal = { }; }
        { AgentIntercomGraphical = { }; }
      ];
    };
  };
  mkConfiguration =
    user:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs horizon user;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        inputs.codex-desktop-linux.homeManagerModules.default
        ../../modules/home/profiles/min/agent-intercom.nix
        {
          home = {
            username = "test-user";
            homeDirectory = "/home/test-user";
            stateVersion = "26.05";
          };
        }
      ];
    }).config;
  mediumUser = {
    name = "test-user";
    size.medium = true;
  };
  smallUser = {
    name = "test-user";
    size.min = true;
  };
  configuration = mkConfiguration mediumUser;
  smallConfiguration = mkConfiguration smallUser;
  profile = pkgs.buildEnv {
    name = "agent-intercom-graphical-tui-profile";
    paths = configuration.home.packages;
  };
  codexCliPackage = pkgs.callPackage ../../packages/codex { inherit inputs; };
  claudeDesktopPackage = inputs.llm-agents.packages.${system}.claude-desktop;
  agentIntercom = lib.removeSuffix "/share/agent-intercom/pi" (
    toString configuration.home.file.".pi/agent/packages/agent-intercom-pi".source
  );
in
assert configuration.programs.codexDesktopLinux.enable;
assert configuration.programs.codexDesktopLinux.cliPackage == codexCliPackage;
assert configuration.programs.codexDesktopLinux.remoteControl.package == codexCliPackage;
assert builtins.elem claudeDesktopPackage configuration.home.packages;
assert !smallConfiguration.programs.codexDesktopLinux.enable;
assert !(builtins.elem claudeDesktopPackage smallConfiguration.home.packages);
pkgs.runCommand "agent-intercom-graphical-tui-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.nodejs
      profile
      agentIntercom
    ];
  }
  ''
    set -eu

    test "$(${profile}/bin/codex --version)" = 'codex-cli 0.149.0'
    test "$(${agentIntercom}/bin/codex-raw --version)" = 'codex-cli 0.149.0'
    test "$(${profile}/bin/claude --version)" = '2.1.241 (Claude Code)'
    test -x ${profile}/bin/codex-desktop
    test -x ${profile}/bin/claude-desktop
    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/cci
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude
    touch "$out"
  ''
