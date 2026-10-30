{ inputs, pkgs, ... }:
let
  guardModule = ../../modules/home/profiles/min/default-opener.nix;
  home = "/tmp/remote-build-command-guard";
  configuration =
    guardEnabled:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        user.size = "Min";
      };
      modules = [
        guardModule
        {
          criomosHome.remoteBuildCommandGuard.enable = guardEnabled;
          home = {
            username = "remote-build-command-guard-check";
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
  flowService =
    guardEnabled:
    let
      module = import ../../modules/home/profiles/min/flow.nix {
        inherit inputs pkgs;
        lib = pkgs.lib;
        user = {
          name = "li";
          size = "Min";
        };
        config = {
          home = {
            username = "li";
            homeDirectory = home;
          };
          criomosHome.flow = {
            enable = true;
            package = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
            stateDirectory = "flow-guard-check";
            solModel = "gpt-6.1-sol";
            landingRepository = null;
            landingDeployRequest = null;
          };
          criomosHome.remoteBuildCommandGuard = {
            enable = guardEnabled;
            directory = guardDirectory;
          };
        };
      };
    in
    module.config.content.systemd.user.services.flow-nexus.Service;
  enabledFlow = flowService true;
  disabledFlow = flowService false;
  ordinaryOutput = inputs.self.homeConfigurations.li.config;
  guardedOutput = inputs.self.homeConfigurations."li-remote-build-guard".config;
in
assert enabled.config.criomosHome.remoteBuildCommandGuard.enable;
assert !disabled.config.criomosHome.remoteBuildCommandGuard.enable;
assert !ordinaryOutput.criomosHome.remoteBuildCommandGuard.enable;
assert guardedOutput.criomosHome.remoteBuildCommandGuard.enable;
assert
  guardedOutput.systemd.user.services.flow-nexus.Service.Environment == enabledFlow.Environment;
assert
  guardedOutput.systemd.user.services.codex-remote-control.Service.Environment == [
    "PATH=${guardDirectory}:%h/.local/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin"
  ];
assert !(disabled.config.home.file ? ".local/libexec/remote-build-command-guard/cargo");
assert !(disabled.config.home.file ? ".local/libexec/remote-build-command-guard/rustc");
assert
  enabledFlow.Environment == [
    "PATH=${guardDirectory}:%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
  ];
assert
  disabledFlow.Environment
  == [ "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin" ];
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

  env -i HOME="$home" PATH="$real" ${pkgs.runtimeShell} -c '
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

  env -i HOME="$home" PATH="$real" ${pkgs.runtimeShell} -c '
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
