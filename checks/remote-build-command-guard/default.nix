{ inputs, pkgs, ... }:
let
  guardModule = ../../modules/home/profiles/min/default-opener.nix;
  home = "/tmp/remote-build-command-guard";
  user = {
    name = "remote-build-command-guard-check";
    size = "Min";
    capabilities = [ ];
  };
  configuration =
    guardEnabled:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs user;
        horizon.node.behavesAs.edge = false;
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
      modules = [
        ../../modules/home/core-packages.nix
        guardModule
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/codex-remote-control.nix
        {
          criomosHome.remoteBuildCommandGuard.enable = guardEnabled;
          home = {
            username = user.name;
            homeDirectory = home;
            stateVersion = "26.05";
          };
        }
      ];
    };
  enabled = configuration true;
  disabled = configuration false;
  guardDirectory = enabled.config.criomosHome.remoteBuildCommandGuard.directory;
  enabledSession = "${enabled.config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
  disabledSession = "${disabled.config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
  cargoGuard = enabled.config.home.file.".local/libexec/remote-build-command-guard/cargo".source;
  rustcGuard = enabled.config.home.file.".local/libexec/remote-build-command-guard/rustc".source;
  ordinaryOutput = disabled.config;
  guardedOutput = enabled.config;
in
assert enabled.config.criomosHome.remoteBuildCommandGuard.enable;
assert !disabled.config.criomosHome.remoteBuildCommandGuard.enable;
assert !ordinaryOutput.criomosHome.remoteBuildCommandGuard.enable;
assert guardedOutput.criomosHome.remoteBuildCommandGuard.enable;
assert
  guardedOutput.systemd.user.services.codex-remote-control.Service.Environment == [
    "PATH=${guardDirectory}:%h/.local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin"
  ];
assert !(disabled.config.home.file ? ".local/libexec/remote-build-command-guard/cargo");
assert !(disabled.config.home.file ? ".local/libexec/remote-build-command-guard/rustc");
pkgs.runCommand "remote-build-command-guard" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  home=${home}
  guard=${guardDirectory}
  real="$TMPDIR/real"
  mkdir -p "$guard" "$home/.local/bin" "$real"
  ln -s ${cargoGuard} "$guard/cargo"
  ln -s ${rustcGuard} "$guard/rustc"
  for command in cargo rustc; do
    cat > "$real/$command" <<EOF
  #!${pkgs.runtimeShell}
  printf '%s\n' real-$command
  EOF
    chmod +x "$real/$command"
  done

  env -i HOME="$home" PATH="$real" home="$home" guard="$guard" real="$real" ${pkgs.runtimeShell} -c '
    set -eu
    . ${enabledSession}
    test "''${PATH%%:*}" = "$guard"
    for command in cargo rustc; do
      test "$(command -v "$command")" = "$guard/$command"
      status=0
      output=$("$command") || status=$?
      test "$status" -eq 1
      test "$output" = "builds run on Prometheus through Nix"
    done
  '

  env -i HOME="$home" PATH="$real" home="$home" guard="$guard" real="$real" ${pkgs.runtimeShell} -c '
    set -eu
    . ${disabledSession}
    test "''${PATH%%:*}" = "$home/.local/bin"
    for command in cargo rustc; do
      test "$(command -v "$command")" = "$real/$command"
      test "$("$command")" = "real-$command"
    done
  '
  touch "$out"
''
