{
  config,
  lib,
  pkgs,
  horizon,
  user,
  ...
}:
let
  cfg = config.criomos.unison;
  synchronizations = user.synchronizations;
  localSynchronizations = builtins.filter (s: s.master == horizon.node.name) synchronizations;
  participates = builtins.any (
    s: s.master == horizon.node.name || s.replica == horizon.node.name
  ) synchronizations;
  serviceName = s: "unison-${builtins.hashString "sha256" (builtins.toJSON s)}";
  profile =
    s:
    let
      localRoot = "${config.home.homeDirectory}/${s.tree}";
      replica = horizon.exNodes.${s.replica};
      remoteRoot = "ssh://${user.name}@${replica.criomeDomainName}/${config.home.homeDirectory}/${s.tree}";
    in
    pkgs.writeText "${serviceName s}.prf" (
      lib.concatStringsSep "\n" (
        [
          "root = ${localRoot}"
          "root = ${remoteRoot}"
          "repeat = watch"
          "batch = true"
          "prefer = ${localRoot}"
          "times = false"
          "sshcmd = ${cfg.sshPackage}/bin/ssh"
          "sshargs = -oBatchMode=yes"
          "servercmd = ${cfg.remoteProgram}"
        ]
        ++ map (name: "ignore = Name ${name}") cfg.ignored
      )
      + "\n"
    );
in
{
  options.criomos.unison = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.unison;
      description = "Unison with its filesystem watcher, installed on both ends.";
    };
    sshPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openssh;
      description = "SSH client used by Unison.";
    };
    remoteProgram = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.profileDirectory}/bin/unison";
      description = "Declared Unison executable on the replica.";
    };
    ignored = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "target"
        "result"
        ".direnv"
      ];
      description = "Basenames excluded from synchronization.";
    };
    identityAgent = lib.mkOption {
      type = lib.types.str;
      default = "%t/gnupg/S.gpg-agent.ssh";
      description = "Existing user SSH agent socket, with systemd specifiers.";
    };
    startLimitBurst = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Maximum service starts within the start limit interval.";
    };
    startLimitInterval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Service manager start limit interval.";
    };
    restartDelay = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Delay after a failed synchronization process.";
    };
  };
  config = lib.mkIf participates {
    assertions = [
      {
        assertion =
          builtins.match "[^\n\r]*" config.home.homeDirectory != null
          && !(lib.hasPrefix " " config.home.homeDirectory)
          && !(lib.hasPrefix "\t" config.home.homeDirectory)
          && !(lib.hasSuffix " " config.home.homeDirectory)
          && !(lib.hasSuffix "\t" config.home.homeDirectory);
        message = "Unison cannot represent home path ${builtins.toJSON config.home.homeDirectory} in its profile";
      }
    ];
    home.packages = [ cfg.package ];
    home.file = builtins.listToAttrs (
      map (
        s: lib.nameValuePair ".unison/${serviceName s}.prf" { source = profile s; }
      ) localSynchronizations
    );
    systemd.user.services = builtins.listToAttrs (
      map (
        s:
        lib.nameValuePair (serviceName s) {
          Unit = {
            Description = "Unison ${s.tree} to ${s.replica}";
            X-Restart-Triggers = [ "${profile s}" ];
            StartLimitBurst = cfg.startLimitBurst;
            StartLimitIntervalSec = cfg.startLimitInterval;
          };
          Service = {
            ExecStart = "${cfg.package}/bin/unison ${serviceName s}";
            Environment = [ "SSH_AUTH_SOCK=${cfg.identityAgent}" ];
            Restart = "on-failure";
            RestartSec = cfg.restartDelay;
          };
          Install.WantedBy = [ "default.target" ];
        }
      ) localSynchronizations
    );
  };
}
