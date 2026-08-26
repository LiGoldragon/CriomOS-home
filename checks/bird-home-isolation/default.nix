{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
  agentIntercomModule = ../../modules/home/profiles/min/agent-intercom.nix;
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
    users.${remoteUser.name} = remoteUser;
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
    lib.${system}.mkUserServiceArtifacts =
      { stateDirectory }:
      let
        stateScript = pkgs.writeShellScript "fake-spirit-state" "exit 0";
        spiritPackage = pkgs.writeShellScriptBin "spirit" "exit 0";
        judgePackage = pkgs.writeShellScriptBin "spirit-judge" "exit 0";
        judgeConfig = pkgs.runCommand "fake-spirit-judge-config" { } "mkdir -p $out";
        judgeProvider = pkgs.writeShellScriptBin "codex" "exit 0";
      in
      {
        paths = {
          inherit stateDirectory;
          socketPath = "${stateDirectory}/spirit.sock";
          metaSocketPath = "${stateDirectory}/meta-spirit.sock";
          judgeSocketPath = "${stateDirectory}/spirit-judge.sock";
          databasePath = "${stateDirectory}/spirit.sema";
          configurationPath = "spirit.config.rkyv";
        };
        packages = {
          spirit = spiritPackage;
          judge = judgePackage;
          inherit judgeConfig judgeProvider;
        };
        daemonConfiguration = stateScript;
        activateState = stateScript;
        initializeState = stateScript;
        initializeJudgeState = stateScript;
        daemonServiceWrapper = pkgs.writeShellScriptBin "spirit-daemon-service" "exit 0";
        judgeServiceWrapper = pkgs.writeShellScriptBin "spirit-judge-daemon-service" "exit 0";
        commandLineWrapper = spiritPackage;
        metaSpiritCommandLineWrapper = pkgs.writeShellScriptBin "meta-spirit" "exit 0";
      };
  };

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
    agentIntercomModule
    orchestrateModule
    spiritModule
  ];
  orchestrateConfiguration = mkHome remoteHorizon { orchestrate = fakeOrchestrate; } [
    orchestrateModule
  ];
  localSpiritConfiguration = mkHome localPersonaHorizon {
    agent = fakeAgent;
    spirit = fakeSpirit;
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
assert remoteConfiguration.config.systemd.user.services ? orchestrate-nexus;
assert remoteConfiguration.config.systemd.user.services ? codex-remote-control;
assert !(remoteConfiguration.config.systemd.user.services ? spirit-judge);
assert !(remoteConfiguration.config.systemd.user.services ? spirit-daemon);
assert orchestrateConfiguration.config.systemd.user.services ? orchestrate-nexus;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-judge;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-daemon;
pkgs.runCommand "bird-home-role-isolation" { } ''
  touch "$out"
''
