{ inputs, pkgs, ... }:
let
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  codexCliPackage = ownedAgentPackages.codexPackage;
  claudeCodePackage = ownedAgentPackages.claudeCodePackage;
  agentIntercom = pkgs.callPackage ../../packages/agent-intercom {
    inherit inputs codexCliPackage claudeCodePackage;
  };
  horizon = {
    users.test-user = {
      name = "test-user";
      size = {
        min = true;
        medium = true;
      };
    };
    node = {
      name = "no-service-fixture";
      behavesAs.edge = false;
      services = [ ];
    };
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs horizon ownedAgentPackages;
        user = horizon.users.test-user;
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      modules = [
        ({ ... }: { _module.args.ownedAgentPackages = ownedAgentPackages; })
        ../../modules/home/core-packages.nix
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
  profile = pkgs.buildEnv {
    name = "agent-intercom-integration-profile";
    paths = configuration.home.packages;
  };
  packageName = package: package.pname or (package.name or "");
  hasPackage = name: builtins.any (package: packageName package == name) configuration.home.packages;
in
assert configuration.home.file ? ".pi/agent/packages/agent-intercom-pi";
assert configuration.home.file ? ".pi/agent/packages/agent-intercom-orchestrator";
assert configuration.home.activation ? mergeAgentIntercomCodexMcp;
assert configuration.home.activation ? mergeAgentIntercomClaudeMcp;
assert hasPackage "agent-intercom-runtime";
assert builtins.elem claudeCodePackage configuration.home.packages;
pkgs.runCommand "agent-intercom-integration-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.nodejs
      profile
    ];
  }
  ''
    set -eu
    mkdir -p "$out"

    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/cci
    test -x ${agentIntercom}/bin/codex-raw
    test -x ${agentIntercom}/bin/claude-raw
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude
    test "$( ${agentIntercom}/bin/codex-raw --version )" = 'codex-cli ${codexCliPackage.version}'
    test "$( ${agentIntercom}/bin/claude-raw --version )" = '${claudeCodePackage.version} (Claude Code)'
    test "$( ${profile}/bin/codex --version )" = 'codex-cli ${codexCliPackage.version}'
    test "$( ${profile}/bin/claude --version )" = '${claudeCodePackage.version} (Claude Code)'

    grep -F -- '--yolo' ${agentIntercom}/bin/coi
    grep -F ${codexCliPackage}/bin/codex ${agentIntercom}/bin/coi
    grep -F -- '--dangerously-skip-permissions' ${agentIntercom}/bin/cci
    grep -F ${claudeCodePackage}/bin/claude ${agentIntercom}/bin/cci

    protocol_home="$TMPDIR/protocol-home"
    mkdir -p "$protocol_home" "$TMPDIR/runtime"
    (
      cd ${agentIntercom}/share/agent-intercom/pi
      HOME="$protocol_home" XDG_RUNTIME_DIR="$TMPDIR/runtime" \
        ${pkgs.nodejs}/bin/node node_modules/tsx/dist/cli.mjs \
          --test --test-concurrency=1 broker/*.test.ts
    )

    touch "$out"
  ''
