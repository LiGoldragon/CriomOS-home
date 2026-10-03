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
  homeFiles = configuration.config.home-files;
  # Distinct store roots model two earlier Home Manager generations. Their
  # names intentionally retain Home Manager's generated-files suffix because
  # checkLinkTargets recognizes ownership by that path class.
  priorHomeFiles = pkgs.runCommand "prior-home-manager-files" { } ''
    mkdir -p "$out/.local/bin"
    ${pkgs.lib.concatMapStringsSep "\n    " (command: "touch \"$out/.local/bin/${command}\"") managedCommands}
  '';
  secondPriorHomeFiles = pkgs.runCommand "second-prior-home-manager-files" { } ''
    mkdir -p "$out/.local/bin"
    ${pkgs.lib.concatMapStringsSep "\n    " (command: "touch \"$out/.local/bin/${command}\"") managedCommands}
  '';
  checkLinkTargets = configuration.config.home.activation.checkLinkTargets.data;
in
# The bindings carry no force: Home Manager's own collision check guards them,
# and no activation step of this module bypasses it.
assert builtins.all (
  command:
  let
    file = managedFiles.".local/bin/${command}";
  in
  file.source == "${messengerClj}/bin/${command}" && !file.force
) managedCommands;
assert !(configuration.config.home.activation ? retireProvenLegacyMessengerBindings);
pkgs.runCommand "messenger-clj-home-package" { } ''
  set -eu
  test -x ${messengerClj}/bin/messenger-clj
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command: "test -x ${messengerClj}/bin/${command}"
  ) compatibilityCommands}
  # Keep all current command entrypoints covered by both the package and the
  # evaluated Home-managed PATH bindings.
  test ${toString (builtins.length compatibilityCommands)} -eq 10

  # Run Home Manager's generated checkLinkTargets step against a home, as
  # activation runs it before linkGeneration.
  generation="$TMPDIR/generation"
  mkdir -p "$generation"
  ln -s ${homeFiles} "$generation/home-files"
  run_link_check() {
    HOME="$1" newGenPath="$generation" \
      PATH=${pkgs.lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.diffutils pkgs.gettext pkgs.ncurses ]} \
      ${pkgs.bash}/bin/bash -eu -c ${pkgs.lib.escapeShellArg checkLinkTargets}
  }

  absent_home="$TMPDIR/absent"
  mkdir -p "$absent_home/.local/bin"
  run_link_check "$absent_home"

  # Two consecutive Home deployments may leave either preceding
  # generated-files root in place when checkLinkTargets runs. Both are Home
  # Manager-owned links and must be admitted without forcing a replacement.
  consecutive_home="$TMPDIR/consecutive"
  mkdir -p "$consecutive_home/.local/bin"
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command:
    "ln -s ${priorHomeFiles}/.local/bin/${command} \"$consecutive_home/.local/bin/${command}\""
  ) managedCommands}
  run_link_check "$consecutive_home"
  rm "$consecutive_home/.local/bin/"*
  ${pkgs.lib.concatMapStringsSep "\n  " (
    command:
    "ln -s ${secondPriorHomeFiles}/.local/bin/${command} \"$consecutive_home/.local/bin/${command}\""
  ) managedCommands}
  run_link_check "$consecutive_home"

  foreign_home="$TMPDIR/foreign"
  mkdir -p "$foreign_home/.local/bin"
  printf foreign > "$foreign_home/.local/bin/hm-send"
  if run_link_check "$foreign_home"; then
    echo "the link check accepted a foreign messenger binding" >&2
    exit 1
  fi

  foreign_link_home="$TMPDIR/foreign-link"
  mkdir -p "$foreign_link_home/.local/bin"
  printf '#!/bin/sh\n' > "$TMPDIR/not-a-messenger-binding"
  ln -s "$TMPDIR/not-a-messenger-binding" "$foreign_link_home/.local/bin/hm-send"
  if run_link_check "$foreign_link_home"; then
    echo "the link check accepted a foreign messenger symlink" >&2
    exit 1
  fi
  touch "$out"
''
