{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  horizon = {
    node = {
      name = "graphical-tui-contract";
      services = [
        { AgentIntercomLocal = { }; }
        { AgentIntercomGraphical = { }; }
      ];
    };
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs horizon;
        user = {
          name = "test-user";
          size.min = true;
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
  profile = pkgs.buildEnv {
    name = "agent-intercom-graphical-tui-profile";
    paths = configuration.home.packages;
  };
  agentIntercom = lib.removeSuffix "/share/agent-intercom/pi" (
    toString configuration.home.file.".pi/agent/packages/agent-intercom-pi".source
  );
in
pkgs.runCommand "agent-intercom-graphical-tui-contract"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.nodejs
      profile
      agentIntercom
    ];
  }
  ''
    set -eu

    test "$( ${profile}/bin/codex --version )" = 'codex-cli 0.149.1'
    test "$( ${profile}/bin/claude --version )" = '2.1.241 (Claude Code)'
    test -x ${agentIntercom}/bin/coi
    test -x ${agentIntercom}/bin/cci
    ! test -e ${agentIntercom}/bin/codex
    ! test -e ${agentIntercom}/bin/claude
    test "$( ${agentIntercom}/bin/codex-raw --version )" = 'codex-cli 0.149.1'
    test -f ${agentIntercom}/share/agent-intercom/claude/node_modules/@dataforxyz/agent-intercom-core/package.json

    ${pkgs.nodejs}/bin/node --input-type=module -e '
      await import("${agentIntercom}/share/agent-intercom/claude/cci.mjs");
    ' </dev/null > "$TMPDIR/cci-adapter.log" 2>&1 &
    cciPid=$!
    sleep 1
    kill "$cciPid" 2>/dev/null || true
    wait "$cciPid" 2>/dev/null || true
    ! grep -F 'ERR_MODULE_NOT_FOUND' "$TMPDIR/cci-adapter.log"

    ${pkgs.nodejs}/bin/node --input-type=module -e '
      await import("${agentIntercom}/share/agent-intercom/claude/ccim.mjs");
    ' </dev/null > "$TMPDIR/ccim-adapter.log" 2>&1 &
    ccimPid=$!
    sleep 1
    kill "$ccimPid" 2>/dev/null || true
    wait "$ccimPid" 2>/dev/null || true
    ! grep -F 'ERR_MODULE_NOT_FOUND' "$TMPDIR/ccim-adapter.log"

    touch "$out"
  ''
