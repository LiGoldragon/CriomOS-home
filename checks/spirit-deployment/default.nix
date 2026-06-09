{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  fakeSpirit = {
    packages.${system}.default = pkgs.runCommand "fake-spirit" { } ''
      mkdir -p "$out/bin"
      cat > "$out/bin/spirit" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'socket=%s\n' "$SPIRIT_SOCKET"
      EOF
      cat > "$out/bin/spirit-daemon" <<'EOF'
      #!${pkgs.runtimeShell}
      printf 'configuration=%s\n' "$1"
      EOF
      cat > "$out/bin/spirit-write-configuration" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      output_path=''${request##* [}
      output_path=''${output_path%])*}
      printf 'fake configuration archive\n' > "$output_path"
      printf '(ConfigurationWritten [%s])\n' "$output_path"
      EOF
      cat > "$out/bin/spirit-migrate-production" <<'EOF'
      #!${pkgs.runtimeShell}
      set -eu
      request=$1
      target_path=''${request##*] [}
      target_path=''${target_path%])*}
      printf 'fake migrated database\n' > "$target_path"
      printf '(Completed 1)\n'
      EOF
      chmod +x "$out/bin/"*
    '';
  };

  moduleResult = import ../../modules/home/profiles/min/spirit.nix {
    inherit pkgs;
    lib = lib // {
      hm.dag.entryAfter = _after: data: { inherit data; };
    };
    inputs.spirit = fakeSpirit;
    config = {
      home.homeDirectory = "/home/li";
      criomosHome.spirit.enable = true;
    };
    user.size.min = true;
  };

  moduleConfiguration =
    if moduleResult.config ? content then moduleResult.config.content else moduleResult.config;

  services = moduleConfiguration.systemd.user.services;
  homePackages = moduleConfiguration.home.packages;
  activation = moduleConfiguration.home.activation.spiritState.data;
  profileWitness = pkgs.symlinkJoin {
    name = "spirit-profile-witness";
    paths = homePackages;
  };

  assertions = [
    {
      condition = builtins.hasAttr "spirit-daemon" services;
      message = "the schema-derived spirit daemon service must exist.";
    }
    {
      condition = !(builtins.hasAttr "persona-spirit-daemon" services);
      message = "the unversioned persona-spirit daemon service must be absent.";
    }
    {
      condition = !(builtins.hasAttr "persona-spirit-daemon-v0.5.2" services);
      message = "the old persona-spirit v0.5.2 daemon service must be absent.";
    }
  ];

  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "spirit-deployment" { } ''
    set -eu

    test -x "${profileWitness}/bin/spirit"
    ! test -e "${profileWitness}/bin/spirit-v0.5.2"
    ! test -e "${profileWitness}/bin/spirit-next"

    SPIRIT_SOCKET=/stale/socket "${profileWitness}/bin/spirit" > current
    grep -q '^socket=/home/li/.local/state/spirit/spirit.sock$' current

    exec_start="${services.spirit-daemon.Service.ExecStart}"
    exec_start_pre="${services.spirit-daemon.Service.ExecStartPre}"

    printf '%s\n' "$exec_start" > exec-start
    printf '%s\n' "$exec_start_pre" > exec-start-pre

    grep -q '/bin/spirit-daemon ' exec-start
    grep -q '/spirit.config.rkyv$' exec-start
    ! grep -q 'spirit-write-configuration' exec-start
    ! grep -q 'persona-spirit' exec-start

    test -s "$(printf '%s\n' "$exec_start" | ${pkgs.gnused}/bin/sed 's|.* ||')"
    grep -q 'spirit-migrate-production' "$exec_start_pre"
    grep -q '/persona-spirit/v0.5.2/persona-spirit.redb' "$exec_start_pre"
    grep -q '/spirit/spirit.sema' "$exec_start_pre"

    grep -q 'spirit-state' ${pkgs.writeText "activation" activation}

    touch "$out"
  ''
