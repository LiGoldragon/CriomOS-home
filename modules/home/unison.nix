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
          "sshargs = ${
            lib.concatStringsSep " " [
              "-F"
              "none"
              "-oBatchMode=yes"
              "-oIdentityAgent=SSH_AUTH_SOCK"
              "-oIdentityFile=none"
              "-oUserKnownHostsFile=none"
              "-oGlobalKnownHostsFile=${cfg.knownHostsFile}"
              "-oStrictHostKeyChecking=yes"
              "-oPreferredAuthentications=publickey"
            ]
          }"
          "servercmd = ${cfg.remoteProgram}"
        ]
        ++ map (name: "ignore = Name ${name}") cfg.ignored
        ++ map (path: "ignore = Path ${path}") cfg.ignoredPaths
      )
      + "\n"
    );
in
{
  options.criomos.unison = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.unison;
      description = "Unison with its filesystem watcher, installed on the master.";
    };
    sshPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openssh;
      description = "SSH client used by Unison.";
    };
    remoteProgram = lib.mkOption {
      type = lib.types.str;
      default = "/run/current-system/sw/bin/unison";
      description = "Declared Unison executable on the replica.";
    };
    knownHostsFile = lib.mkOption {
      type = lib.types.strMatching "[^[:space:]]+";
      default = "/etc/ssh/ssh_known_hosts";
      description = "Cluster host keys declared by CriomOS, used exclusively; its path must be one Unison sshargs token.";
    };
    ignored = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "target"
        "result"
        "result-*"
        ".direnv"
      ];
      description = "Basenames excluded from synchronization.";
    };
    ignoredPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "staging" ];
      description = "Paths under the tree's root excluded from synchronization; staging holds worktrees that link back into this node's /git.";
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
      type = lib.types.ints.positive;
      default = 300;
      description = "Positive service manager start limit interval in seconds.";
    };
    restartDelay = lib.mkOption {
      type = lib.types.str;
      default = "5s";
      description = "Delay after a failed synchronization process.";
    };
  };
  config = lib.mkIf (localSynchronizations != [ ]) {
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
