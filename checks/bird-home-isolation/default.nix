{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
  orchestrateModule = ../../modules/home/profiles/min/orchestrate.nix;
  spiritModule = ../../modules/home/profiles/min/spirit.nix;

  remoteHorizon = {
    node = {
      behavesAs.edge = true;
      services = [ ];
      typeIs.largeAiRouter = false;
      behavesAs.largeAi = false;
      criomeDomainName = "edge.invalid";
    };
    exNodes = { };
  };
  localPersonaHorizon = {
    node = remoteHorizon.node // {
      services = [
        {
          PersonaDevelopment = {
            capabilities = [ ];
          };
        }
      ];
    };
    exNodes = { };
  };
  remoteUser = {
    name = "remote-user";
    size.min = true;
  };
  fakeOrchestrate = {
    packages.${system}.default = pkgs.writeShellScriptBin "orchestrate" "exit 0";
  };
  fakeAgent = {
    packages.${system}.default = pkgs.writeShellScriptBin "agent" "exit 0";
  };
  fakeSpirit = {
    packages.${system}.default = pkgs.writeShellScriptBin "spirit" "exit 0";
  };
  fakeSpiritJudge = {
    packages.${system}.default = pkgs.writeShellScriptBin "spirit-judge" "exit 0";
  };
  fakeCodex = {
    packages.${system}.default = pkgs.writeShellScriptBin "codex" "exit 0";
  };
  fakeSpiritJudgeConfig = pkgs.runCommand "spirit-judge-config" { } "mkdir -p $out";

  mkHome =
    horizon: extraInputs: modules:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inputs = inputs // extraInputs;
        inherit horizon;
        user = remoteUser;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = modules ++ [
        {
          home = {
            username = remoteUser.name;
            homeDirectory = "/home/${remoteUser.name}";
            stateVersion = "26.05";
          };
        }
      ];
    };

  remoteConfiguration = mkHome remoteHorizon { } [
    piModelsModule
    orchestrateModule
    spiritModule
  ];
  localOrchestrateConfiguration = mkHome localPersonaHorizon { orchestrate = fakeOrchestrate; } [
    orchestrateModule
  ];
  localSpiritConfiguration = mkHome localPersonaHorizon {
    agent = fakeAgent;
    spirit = fakeSpirit;
    spirit-judge = fakeSpiritJudge;
    spirit-judge-config = fakeSpiritJudgeConfig;
    codex-cli = fakeCodex;
  } [ spiritModule ];

  remoteFiles = remoteConfiguration.config.home.file;
  remoteActivation = remoteConfiguration.config.home.activation;
in
assert remoteFiles ? ".pi/agent/SYSTEM.md";
assert remoteFiles ? ".pi-testing/agent/SYSTEM.md";
assert remoteFiles ? ".pi/agent/packages/pi-linkup";
assert remoteFiles ? ".pi-testing/agent/packages/pi-linkup";
assert remoteFiles ? ".pi/agent/packages/pi-subagents";
assert remoteFiles ? ".pi-testing/agent/packages/pi-subagents";
assert remoteActivation ? preparePiPackageSymlink;
assert
  builtins.length (
    builtins.filter (name: pkgs.lib.hasPrefix "mergePi" name) (builtins.attrNames remoteActivation)
  ) == 8;
assert !(remoteConfiguration.config.systemd.user.services ? orchestrate-daemon);
assert !(remoteConfiguration.config.systemd.user.services ? spirit-judge);
assert !(remoteConfiguration.config.systemd.user.services ? spirit-daemon);
assert localOrchestrateConfiguration.config.systemd.user.services ? orchestrate-daemon;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-judge;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-daemon;
pkgs.runCommand "bird-home-role-isolation" { } ''
  touch "$out"
''
