{
  config,
  lib,
  pkgs,
  inputs,
  horizon,
  user,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  orchestratePackage = inputs.orchestrate.packages.${system}.default;
  legacyOrchestratePackage = inputs.orchestrate-legacy.packages.${system}.default;
  serviceName =
    service:
    if builtins.isString service then
      service
    else if builtins.isAttrs service then
      let
        names = builtins.attrNames service;
      in
      if builtins.length names == 1 then builtins.head names else null
    else
      null;
  isPersonaDevelopment = builtins.any (service: serviceName service == "PersonaDevelopment") (
    horizon.node.services or [ ]
  );

  orchestrateProfilePackage =
    pkgs.runCommand "${orchestratePackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p $out/bin
        for binary in ${orchestratePackage}/bin/*; do
          ln -s "$binary" "$out/bin/$(basename "$binary")"
        done
        ln -s ${legacyOrchestratePackage}/bin/orchestrate-write-configuration \
          $out/bin/orchestrate-write-configuration
        rm $out/bin/orchestrate $out/bin/meta-orchestrate
        makeWrapper ${orchestratePackage}/bin/orchestrate $out/bin/orchestrate \
          --run 'export PERSONA_ORCHESTRATE_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/orchestrate/orchestrate.sock"'
        makeWrapper ${orchestratePackage}/bin/meta-orchestrate $out/bin/meta-orchestrate \
          --run 'export PERSONA_ORCHESTRATE_META_SOCKET="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/orchestrate/orchestrate-owner.sock"'
      '';

  # The orchestrate daemon supervises the multi-agent claim/coordination
  # fabric for the `primary` workspace under this user's home. Runtime state is
  # intentionally outside the workspace: the Sema store lives under XDG state,
  # while sockets live under the user runtime directory so stale process
  # endpoints disappear with the login session.
  stateDirectory = "${config.xdg.stateHome}/orchestrate";
  storePath = "${stateDirectory}/orchestrate.sema";
  runtimeDirectory = "%t/orchestrate";
  ordinarySocketPath = "${runtimeDirectory}/orchestrate.sock";
  metaSocketPath = "${runtimeDirectory}/orchestrate-owner.sock";
  upgradeSocketPath = "${runtimeDirectory}/orchestrate-upgrade.sock";
  workspaceRoot = "${config.home.homeDirectory}/primary";
  gitIndexRoot = "/git/github.com/LiGoldragon";
  # The co-resident messenger's working socket (the message module's unit
  # binds it): the orchestrator pushes minted identities and discovered
  # endpoints there. The router label stays absent — no router is deployed,
  # and the direct labeled daemon argument makes messenger-without-router a
  # truthful configuration. The required workspace and Git-index paths remain
  # typed daemon state inputs; the pinned source does not inspect or manage
  # either host path.
  messengerSocketPath = "%t/message/message.sock";
in
{
  options.criomosHome.orchestrate = {
    enable = mkOption {
      type = bool;
      default = isPersonaDevelopment;
      description = "Supervise the orchestrate multi-agent claim/coordination daemon only on a Horizon PersonaDevelopment node.";
    };
  };

  config = mkIf (size.min && isPersonaDevelopment && config.criomosHome.orchestrate.enable) {
    home.packages = [ orchestrateProfilePackage ];

    systemd.user.services.orchestrate-daemon = {
      Unit = {
        Description = "Orchestrate multi-agent claim/coordination daemon";
        # Bound restart storms: if the signal file or a socket is
        # transiently unavailable the unit backs off instead of spinning.
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        # The direct startup contract has no configuration writer. Systemd owns
        # the store and socket parents; Orchestrate owns only its Sema state and
        # configured Unix sockets beneath them.
        StateDirectory = "orchestrate";
        RuntimeDirectory = "orchestrate";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${orchestratePackage}/bin/orchestrate-daemon ${storePath} ${ordinarySocketPath} ${metaSocketPath} ${upgradeSocketPath} ${workspaceRoot} ${gitIndexRoot} messenger=${messengerSocketPath}";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      # default.target is reached on user login, so the daemon starts on login.
      Install.WantedBy = [ "default.target" ];
    };
  };
}
