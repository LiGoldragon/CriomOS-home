{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  ownedAgentModule = { ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; };
  piModelsModule = ../../modules/home/profiles/min/pi-models.nix;
  codexRemoteControlModule = ../../modules/home/profiles/min/codex-remote-control.nix;
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
    users = [ remoteUser ];
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
    size = "Min";
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
        inherit horizon ownedAgentPackages;
        user = remoteUser;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        ownedAgentModule
        ../../modules/home/core-packages.nix
      ]
      ++ modules
      ++ [
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
    codexRemoteControlModule
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
  retireLegacyPiIntercomBrokerOverrides = remoteActivation.retireLegacyPiIntercomBrokerOverrides.data;
in
assert remoteFiles ? ".pi/agent/SYSTEM.md";
assert remoteFiles ? ".pi-testing/agent/SYSTEM.md";
assert remoteFiles ? ".pi/agent/packages/pi-linkup";
assert remoteFiles ? ".pi-testing/agent/packages/pi-linkup";
assert remoteFiles ? ".pi/agent/packages/pi-subagents";
assert remoteFiles ? ".pi-testing/agent/packages/pi-subagents";
assert !(remoteFiles ? ".pi/agent/intercom/config.json");
assert !(remoteFiles ? ".pi-testing/agent/intercom/config.json");
assert remoteActivation ? preparePiPackageSymlink;
assert
  builtins.length (
    builtins.filter (name: pkgs.lib.hasPrefix "mergePi" name) (builtins.attrNames remoteActivation)
  ) == 6;
assert !(remoteActivation ? mergePiIntercomConfig);
assert !(remoteActivation ? mergePiTestingIntercomConfig);
assert remoteActivation ? retireLegacyPiIntercomBrokerOverrides;
assert remoteConfiguration.config.systemd.user.services ? orchestrate-nexus;
assert remoteConfiguration.config.systemd.user.services ? codex-remote-control;
assert !(remoteConfiguration.config.systemd.user.services ? spirit-judge);
assert !(remoteConfiguration.config.systemd.user.services ? spirit-daemon);
assert orchestrateConfiguration.config.systemd.user.services ? orchestrate-nexus;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-judge;
assert localSpiritConfiguration.config.systemd.user.services ? spirit-daemon;
pkgs.runCommand "bird-home-role-isolation" { } ''
  set -eu

  run_retirement() {
    HOME="$1" ${pkgs.bash}/bin/bash -eu -c \
      ${pkgs.lib.escapeShellArg retireLegacyPiIntercomBrokerOverrides}
  }

  legacy_node=/nix/store/0123456789abcdfghijklmnpqrsvwxyz-nodejs-22.14.0/bin/node
  legacy_runner=/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-agent-intercom-0.7.0/share/agent-intercom/pi/node_modules/tsx/dist/cli.mjs

  legacy_home="$TMPDIR/legacy"
  mkdir -p "$legacy_home/.pi/agent/intercom" "$legacy_home/.pi-testing/agent/intercom"
  ${pkgs.jq}/bin/jq -n --arg command "$legacy_node" --arg runner "$legacy_runner" \
    '{ enabled: true, brokerCommand: $command, brokerArgs: [$runner], unknown: { keep: 7 } }' \
    > "$legacy_home/.pi/agent/intercom/config.json"
  cp "$legacy_home/.pi/agent/intercom/config.json" \
    "$legacy_home/.pi-testing/agent/intercom/config.json"
  chmod 600 "$legacy_home/.pi/agent/intercom/config.json" \
    "$legacy_home/.pi-testing/agent/intercom/config.json"

  run_retirement "$legacy_home"
  for config in \
    "$legacy_home/.pi/agent/intercom/config.json" \
    "$legacy_home/.pi-testing/agent/intercom/config.json"; do
    ${pkgs.jq}/bin/jq -e \
      '(has("brokerCommand") | not) and (has("brokerArgs") | not) and .enabled and .unknown.keep == 7' \
      "$config" >/dev/null
    test "$(stat -c %a "$config")" = 600
  done

  native_inode="$(stat -c %i "$legacy_home/.pi/agent/intercom/config.json")"
  testing_inode="$(stat -c %i "$legacy_home/.pi-testing/agent/intercom/config.json")"
  run_retirement "$legacy_home"
  test "$(stat -c %i "$legacy_home/.pi/agent/intercom/config.json")" = "$native_inode"
  test "$(stat -c %i "$legacy_home/.pi-testing/agent/intercom/config.json")" = "$testing_inode"

  custom_home="$TMPDIR/custom"
  mkdir -p "$custom_home/.pi/agent/intercom" "$custom_home/.pi-testing/agent/intercom"
  ${pkgs.jq}/bin/jq -n \
    '{ brokerCommand: "/opt/intercom/bin/node", brokerArgs: ["/opt/intercom/runner.mjs"], custom: true }' \
    > "$custom_home/.pi/agent/intercom/config.json"
  ${pkgs.jq}/bin/jq -n --arg command "$legacy_node" \
    '{ brokerCommand: $command, partial: true }' \
    > "$custom_home/.pi-testing/agent/intercom/config.json"
  cp "$custom_home/.pi/agent/intercom/config.json" "$TMPDIR/custom-before.json"
  cp "$custom_home/.pi-testing/agent/intercom/config.json" "$TMPDIR/partial-before.json"
  run_retirement "$custom_home"
  cmp "$TMPDIR/custom-before.json" "$custom_home/.pi/agent/intercom/config.json"
  cmp "$TMPDIR/partial-before.json" "$custom_home/.pi-testing/agent/intercom/config.json"

  absent_home="$TMPDIR/absent"
  mkdir -p "$absent_home"
  run_retirement "$absent_home"
  test ! -e "$absent_home/.pi"
  test ! -e "$absent_home/.pi-testing"

  touch "$out"
''
