{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  makeFakeInput =
    version:
    let
      safeVersion = builtins.replaceStrings [ "." ] [ "-" ] version;
    in
    {
      packages.${system} = {
        spirit = pkgs.writeShellScriptBin "spirit" ''
          printf 'version=%s\nordinary=%s\nowner=%s\n' \
            ${lib.escapeShellArg version} \
            "$PERSONA_SPIRIT_SOCKET" \
            "$PERSONA_SPIRIT_OWNER_SOCKET"
        '';
        spirit-next = pkgs.writeShellScriptBin "spirit-next" ''
          printf 'version=%s\nordinary=%s\nowner=%s\n' \
            ${lib.escapeShellArg version} \
            "$PERSONA_SPIRIT_NEXT_SOCKET" \
            "$PERSONA_SPIRIT_NEXT_OWNER_SOCKET"
        '';
        persona-spirit-daemon = pkgs.writeShellScriptBin "persona-spirit-daemon" ''
          printf 'daemon=%s\nconfiguration=%s\n' ${lib.escapeShellArg version} "$1"
        '';
        spirit-migrate-0-3-to-0-4 = pkgs.writeShellScriptBin "spirit-migrate-0-3-to-0-4" ''
          printf '(MigrationCompleted 0)\n'
        '';
        spirit-migrate-0-4-to-0-5 = pkgs.writeShellScriptBin "spirit-migrate-0-4-to-0-5" ''
          printf '(MigrationCompleted 0)\n'
        '';
        spirit-migrate-0-5-to-0-5-2 = pkgs.writeShellScriptBin "spirit-migrate-0-5-to-0-5-2" ''
          printf '(MigrationCompleted 0)\n'
        '';
      };
      name = "fake-persona-spirit-${safeVersion}";
    };

  moduleResult = import ../../modules/home/profiles/min/spirit.nix {
    inherit lib pkgs;
    inputs = {
      "persona-spirit-v0-1-0" = makeFakeInput "v0.1.0";
      "persona-spirit-v0-1-1" = makeFakeInput "v0.1.1";
      "persona-spirit-v0-2-0" = makeFakeInput "v0.2.0";
      "persona-spirit-v0-3-0" = makeFakeInput "v0.3.0";
      "persona-spirit-v0-4-0" = makeFakeInput "v0.4.0";
      "persona-spirit-v0-4-1" = makeFakeInput "v0.4.1";
      "persona-spirit-v0-4-2" = makeFakeInput "v0.4.2";
      "persona-spirit-v0-5-0" = makeFakeInput "v0.5.0";
      "persona-spirit-v0-5-1" = makeFakeInput "v0.5.1";
      "persona-spirit-v0-5-2" = makeFakeInput "v0.5.2";
      persona-spirit-next = makeFakeInput "next";
    };
    config = {
      home.homeDirectory = "/home/li";
      criomosHome.personaSpirit = {
        deployedVersions = [
          "v0.1.0"
          "v0.1.1"
          "v0.2.0"
          "v0.3.0"
          "v0.4.0"
          "v0.4.1"
          "v0.4.2"
          "v0.5.0"
          "v0.5.1"
          "v0.5.2"
          "next"
        ];
        currentDefault = "v0.5.2";
      };
    };
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;

  services = moduleConfiguration.systemd.user.services;
  homePackages = moduleConfiguration.home.packages;
  profileWitness = pkgs.symlinkJoin {
    name = "persona-spirit-versioned-profile-witness";
    paths = homePackages;
  };

  serviceAssertions = [
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.1.0" services;
      message = "persona-spirit v0.1.0 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.1.1" services;
      message = "persona-spirit v0.1.1 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.2.0" services;
      message = "persona-spirit v0.2.0 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.3.0" services;
      message = "persona-spirit v0.3.0 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.4.0" services;
      message = "persona-spirit v0.4.0 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.4.1" services;
      message = "persona-spirit v0.4.1 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.4.2" services;
      message = "persona-spirit v0.4.2 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.5.0" services;
      message = "persona-spirit v0.5.0 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.5.1" services;
      message = "persona-spirit v0.5.1 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-v0.5.2" services;
      message = "persona-spirit v0.5.2 daemon service must exist.";
    }
    {
      condition = builtins.hasAttr "persona-spirit-daemon-next" services;
      message = "persona-spirit next daemon service must exist.";
    }
    {
      condition = !(builtins.hasAttr "persona-spirit-daemon" services);
      message = "the unversioned persona-spirit daemon service must be absent.";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) serviceAssertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "persona-spirit-versioned-deployment" { } ''
    set -eu

    test -x "${profileWitness}/bin/spirit-v0.1.0"
    test -x "${profileWitness}/bin/spirit-v0.1.1"
    test -x "${profileWitness}/bin/spirit-v0.2.0"
    test -x "${profileWitness}/bin/spirit-v0.3.0"
    test -x "${profileWitness}/bin/spirit-v0.4.0"
    test -x "${profileWitness}/bin/spirit-v0.4.1"
    test -x "${profileWitness}/bin/spirit-v0.4.2"
    test -x "${profileWitness}/bin/spirit-v0.5.0"
    test -x "${profileWitness}/bin/spirit-v0.5.1"
    test -x "${profileWitness}/bin/spirit-v0.5.2"
    test -x "${profileWitness}/bin/spirit-next"
    test -x "${profileWitness}/bin/spirit"

    grep -q '/persona-spirit/v0.1.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.1.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.1.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.1.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.1.1".Service.ExecStart}"
    ! grep -q '/persona-spirit/v0.1.1/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.1.1".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.1.1".Service.ExecStart}"
    grep -q '/persona-spirit/v0.2.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.2.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.2.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.2.0".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.2.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.3.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.3.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.3.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.3.0".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.3.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.4.0".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.4.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.1".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.1/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.4.1".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.4.1".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.2/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.2".Service.ExecStart}"
    grep -q '/persona-spirit/v0.4.2/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.4.2".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.4.2".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.5.0".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.5.0".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.1".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.1/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.5.1".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.5.1".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.2/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.2".Service.ExecStart}"
    grep -q '/persona-spirit/v0.5.2/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.5.2".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-v0.5.2".Service.ExecStart}"
    grep -q '/persona-spirit/next/persona-spirit.redb' \
      "${services."persona-spirit-daemon-next".Service.ExecStart}"
    grep -q '/persona-spirit/next/upgrade.sock' \
      "${services."persona-spirit-daemon-next".Service.ExecStart}"
    ! grep -q '"' "${services."persona-spirit-daemon-next".Service.ExecStart}"
    grep -q '/persona-spirit/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/spirit.sock' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.1.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"
    grep -q 'spirit-migrate-0-3-to-0-4' \
      "${services."persona-spirit-daemon-v0.4.1".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.3.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.1".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.4.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.1".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.4.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.2".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.4.2/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.4.2".Service.ExecStartPre}"
    grep -q 'spirit-migrate-0-4-to-0-5' \
      "${services."persona-spirit-daemon-v0.5.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.4.2/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.5.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.5.0/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.1".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.5.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.1".Service.ExecStartPre}"
    grep -q 'spirit-migrate-0-5-to-0-5-2' \
      "${services."persona-spirit-daemon-v0.5.2".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.5.1/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.2".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.5.2/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.5.2".Service.ExecStartPre}"

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.1.0" > v0-1-0
    grep -q '^version=v0.1.0$' v0-1-0
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.1.0/spirit.sock$' v0-1-0
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.1.0/owner.sock$' v0-1-0

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.1.1" > v0-1-1
    grep -q '^version=v0.1.1$' v0-1-1
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.1.1/spirit.sock$' v0-1-1
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.1.1/owner.sock$' v0-1-1

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.2.0" > v0-2-0
    grep -q '^version=v0.2.0$' v0-2-0
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.2.0/spirit.sock$' v0-2-0
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.2.0/owner.sock$' v0-2-0

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.3.0" > v0-3-0
    grep -q '^version=v0.3.0$' v0-3-0
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.3.0/spirit.sock$' v0-3-0
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.3.0/owner.sock$' v0-3-0

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.4.0" > v0-4-0
    grep -q '^version=v0.4.0$' v0-4-0
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.4.0/spirit.sock$' v0-4-0
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.4.0/owner.sock$' v0-4-0

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.4.1" > v0-4-1
    grep -q '^version=v0.4.1$' v0-4-1
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.4.1/spirit.sock$' v0-4-1
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.4.1/owner.sock$' v0-4-1

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.4.2" > v0-4-2
    grep -q '^version=v0.4.2$' v0-4-2
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.4.2/spirit.sock$' v0-4-2
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.4.2/owner.sock$' v0-4-2

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.5.0" > v0-5-0
    grep -q '^version=v0.5.0$' v0-5-0
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.5.0/spirit.sock$' v0-5-0
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.5.0/owner.sock$' v0-5-0

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.5.1" > v0-5-1
    grep -q '^version=v0.5.1$' v0-5-1
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.5.1/spirit.sock$' v0-5-1
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.5.1/owner.sock$' v0-5-1

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-v0.5.2" > v0-5-2
    grep -q '^version=v0.5.2$' v0-5-2
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/v0.5.2/spirit.sock$' v0-5-2
    grep -q '^owner=/home/li/.local/state/persona-spirit/v0.5.2/owner.sock$' v0-5-2

    PERSONA_SPIRIT_SOCKET=/stale/ordinary \
      PERSONA_SPIRIT_OWNER_SOCKET=/stale/owner \
      "${profileWitness}/bin/spirit-next" > next
    grep -q '^version=next$' next
    grep -q '^ordinary=/home/li/.local/state/persona-spirit/next/spirit.sock$' next
    grep -q '^owner=/home/li/.local/state/persona-spirit/next/owner.sock$' next

    "${profileWitness}/bin/spirit" > current
    grep -q '^version=v0.5.2$' current

    touch "$out"
  ''
