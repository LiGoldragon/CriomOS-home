{
  config,
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;

  system = pkgs.stdenv.hostPlatform.system;
  messagePackage = inputs.message.packages.${system}.default;

  # Message 0.16.0 is the durable message ledger and nothing else: it writes
  # no pane, and every delivery it makes is Flow's `Deliver` over Flow's meta
  # socket. The Nexus is `message-nexus`, started with no arguments — it reads
  # HOME and XDG_RUNTIME_DIR and nothing more, creates its own state
  # directory, and persists its socket and Flow-socket paths in its store on
  # first open. There is no configuration writer and no signal file to hand
  # it, so the unit supplies neither.
  #
  # Its clients are `message` and `message-meta`, which default to
  # `$XDG_RUNTIME_DIR/message/message.sock` and `message-owner.sock` — the
  # very paths the Nexus serves — so the package is installed unwrapped.
  # The Nexus's own store is `${stateDirectory}/message.sema`; it opens and
  # creates it itself, so nothing here names it but this comment.
  stateDirectory = "${config.xdg.stateHome}/message";

  # The 0.14 messenger store is never opened by 0.16: no record kind survives
  # and nothing is migrated. It is moved aside rather than removed, because it
  # holds the only copy of the retired ledger. The step is idempotent — with
  # the retired store already aside it does nothing — and it refuses rather
  # than overwrite an existing snapshot, so no ledger can be lost to a second
  # activation.
  retiredDirectory = "${stateDirectory}/retired-0.14";
  retireStoreScript = pkgs.writeShellScript "message-retire-messenger-store" ''
    set -eu
    state=${lib.escapeShellArg stateDirectory}
    retired=${lib.escapeShellArg retiredDirectory}

    ${pkgs.coreutils}/bin/mkdir -p "$state" "$retired"
    for name in messenger.sema message-daemon.signal; do
      for candidate in "$state/$name" "$state/$name".*; do
        [ -e "$candidate" ] || continue
        target="$retired/$(${pkgs.coreutils}/bin/basename "$candidate")"
        if [ -e "$target" ]; then
          echo "Refusing to retire Message 0.14 state: $target already exists" >&2
          exit 1
        fi
        ${pkgs.coreutils}/bin/mv -- "$candidate" "$target"
        echo "Retired Message 0.14 state: $candidate -> $target"
      done
    done
  '';
in
{
  options.criomosHome.message = {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Supervise the Message Nexus as a systemd --user service.";
    };
  };

  config = mkIf (sizeAtLeast "Min" && config.criomosHome.message.enable) {
    home.packages = [ messagePackage ];

    # Flow admits this exact executable on its meta socket. The value is the
    # store path of the binary the unit runs, which is what Flow reads back
    # from `/proc/<pid>/exe`.
    criomosHome.flow.messageNexusPath = "${messagePackage}/bin/message-nexus";

    home.activation.retireMessengerStore = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${retireStoreScript}
    '';

    systemd.user.services.message-nexus = {
      Unit = {
        Description = "Message Nexus — durable message ledger";
        # Message delivers through Flow's meta socket, lazily per delivery, so
        # an absent Flow degrades a delivery and never startup.
        After = [ "flow-nexus.service" ];
        Wants = [ "flow-nexus.service" ];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        Type = "simple";
        RuntimeDirectory = "message";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${messagePackage}/bin/message-nexus";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
