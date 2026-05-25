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
        persona-spirit-daemon = pkgs.writeShellScriptBin "persona-spirit-daemon" ''
          printf 'daemon=%s\nconfiguration=%s\n' ${lib.escapeShellArg version} "$1"
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
    };
    config = {
      home.homeDirectory = "/home/li";
      criomosHome.personaSpirit = {
        deployedVersions = [
          "v0.1.0"
          "v0.1.1"
          "v0.2.0"
        ];
        currentDefault = "v0.1.0";
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
    grep -q '/persona-spirit/persona-spirit.redb' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/spirit.sock' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"
    grep -q '/persona-spirit/v0.1.0/upgrade.sock' \
      "${services."persona-spirit-daemon-v0.1.0".Service.ExecStartPre}"

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

    "${profileWitness}/bin/spirit" > current
    grep -q '^version=v0.1.0$' current

    touch "$out"
  ''
