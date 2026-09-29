{ inputs, pkgs, ... }:
let
  messengerClj = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  compatibilityCommands = [
    "hm-send"
    "hm-send-abrupt"
    "hm-list"
    "hm-register"
    "hm-repair"
    "hm-deregister"
    "hm-rebind"
    "hm-move"
    "hm-retire"
    "hm-heartbeat-state"
  ];
  managedCommands = [ "messenger-clj" ] ++ compatibilityCommands;
  legacyMessengerClj = "/nix/store/p8mz1msm8lxiahnw6sfipi8m258x1q3z-messenger-clj-0.2.5";
  configuration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        name = "messenger-check";
        size = "Min";
      };
    };
    modules = [
      ../../modules/home/profiles/min/messenger-clj.nix
      {
        home = {
          username = "messenger-check";
          homeDirectory = "/tmp/messenger-check";
          stateVersion = "26.05";
        };
      }
    ];
  };
  managedFiles = configuration.config.home.file;
  retireLegacyBindings =
    configuration.config.home.activation.retireProvenLegacyMessengerBindings.data;
in
assert builtins.all (
  command:
  let
    file = managedFiles.".local/bin/${command}";
  in
  file.source == "${messengerClj}/bin/${command}" && file.force
) managedCommands;
pkgs.runCommand "messenger-clj-home-package" { } ''
  set -eu
  test -x ${messengerClj}/bin/messenger-clj
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command: "test -x ${messengerClj}/bin/${command}"
  ) compatibilityCommands}
  # Keep all current command entrypoints covered by both the package and the
  # evaluated Home-managed PATH bindings.
  test ${toString (builtins.length compatibilityCommands)} -eq 10

  run_retirement_guard() {
    PATH="$readlink_bin:$PATH" HOME="$1" ${pkgs.bash}/bin/bash -eu -c ${pkgs.lib.escapeShellArg retireLegacyBindings}
  }

  readlink_bin="$TMPDIR/readlink-bin"
  mkdir -p "$readlink_bin"
  cat > "$readlink_bin/readlink" <<'EOF'
  #!${pkgs.runtimeShell}
  if [ "$1" = -f ]; then
    case "$2" in
      "$TEST_LEGACY_HOME"/.local/bin/*)
        command="''${2##*/}"
        printf '%s\n' "$TEST_LEGACY_PACKAGE/bin/$command"
        exit 0
        ;;
    esac
  fi
  exec ${pkgs.coreutils}/bin/readlink "$@"
  EOF
  chmod +x "$readlink_bin/readlink"

  absent_home="$TMPDIR/absent"
  mkdir -p "$absent_home/.local/bin"
  run_retirement_guard "$absent_home"

  legacy_home="$TMPDIR/legacy"
  mkdir -p "$legacy_home/.local/bin" "$legacy_home/.local/libexec"
  ln -s ${legacyMessengerClj} "$legacy_home/.local/libexec/messenger-clj"
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command:
    "ln -s \"$legacy_home/.local/libexec/messenger-clj/bin/${command}\" \"$legacy_home/.local/bin/${command}\""
  ) managedCommands}
  export TEST_LEGACY_HOME="$legacy_home"
  export TEST_LEGACY_PACKAGE=${legacyMessengerClj}
  run_retirement_guard "$legacy_home"

  foreign_home="$TMPDIR/foreign"
  mkdir -p "$foreign_home/.local/bin"
  printf foreign > "$foreign_home/.local/bin/hm-send"
  if run_retirement_guard "$foreign_home"; then
    echo "the retirement guard accepted a foreign messenger binding" >&2
    exit 1
  fi
  touch "$out"
''
