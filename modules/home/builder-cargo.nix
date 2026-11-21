# One command that runs Cargo on the builder in the synchronized work tree
# (night order 21 Nov, line 5; Fable ruling bwv8). An edit made here under the
# tree Unison carries to the builder, then `builder-cargo build` (any Cargo
# arguments) runs the builder's real Cargo in the same directory there. Before
# it runs, the command compares the git work tree here and there once, and
# refuses, naming the difference, while Unison has not yet carried an edit.
#
# By default it exists where this node is the master of a synchronization
# whose replica is one of this node's Nix builders; the builder host, the tree
# and the builder's PATH are configuration.
{
  config,
  lib,
  pkgs,
  horizon,
  user,
  ...
}:
let
  cfg = config.criomosHome.builderCargo;
  builderHostNames = map (builder: builder.hostName) (horizon.node.builderConfigs or [ ]);
  replicaHostName = s: horizon.exNodes.${s.replica}.criomeDomainName or null;
  builderSynchronizations = builtins.filter (
    s: s.master == horizon.node.name && builtins.elem (replicaHostName s) builderHostNames
  ) (user.synchronizations or [ ]);
  synchronization = if builderSynchronizations == [ ] then null else builtins.head builderSynchronizations;

  command = pkgs.writeShellApplication {
    name = cfg.commandName;
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.findutils
      config.criomos.unison.sshPackage
    ];
    text = ''
      tree=${lib.escapeShellArg "${config.home.homeDirectory}/${cfg.tree}"}
      host=${lib.escapeShellArg cfg.host}
      remote_path=${lib.escapeShellArg cfg.remotePath}
      here=$(pwd -P)
      case "$here/" in
        "$tree"/*) ;;
        *)
          printf '%s: %s is outside the synchronized tree %s\n' ${lib.escapeShellArg cfg.commandName} "$here" "$tree" >&2
          exit 2
          ;;
      esac

      digest='git ls-files -z -c -o --exclude-standard | sort -z | xargs -0 -r sha256sum | sha256sum'
      local_digest=$(sh -c "$digest")
      remote_digest=$(ssh -o BatchMode=yes "$host" "PATH=$(printf '%q' "$remote_path"):\$PATH; cd $(printf '%q' "$here") && $digest")
      if [ "$local_digest" != "$remote_digest" ]; then
        printf '%s: the work tree at %s differs on %s; Unison has not carried the last edit yet\n' \
          ${lib.escapeShellArg cfg.commandName} "$here" "$host" >&2
        exit 3
      fi

      terminal=()
      if [ -t 1 ]; then terminal=(-t); fi
      exec ssh -o BatchMode=yes "''${terminal[@]}" "$host" \
        "PATH=$(printf '%q' "$remote_path"):\$PATH; cd $(printf '%q' "$here") && exec cargo $(printf '%q ' "$@")"
    '';
  };
in
{
  options.criomosHome.builderCargo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = synchronization != null;
      description = "Declare the command that runs Cargo on the builder in the synchronized work tree.";
    };
    commandName = lib.mkOption {
      type = lib.types.str;
      default = "builder-cargo";
      description = "The name of the command.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = if synchronization == null then "" else replicaHostName synchronization;
      description = "The builder the command runs Cargo on, reached over SSH as the user.";
    };
    tree = lib.mkOption {
      type = lib.types.str;
      default = if synchronization == null then "" else synchronization.tree;
      description = "The synchronized tree under the home directory, the same place on both nodes.";
    };
    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.nix-profile/bin:/run/current-system/sw/bin";
      description = "The PATH prefix on the builder where its real Cargo, git and coreutils are found.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.host != "" && cfg.tree != "";
        message = "criomosHome.builderCargo needs a builder host and a synchronized tree.";
      }
    ];
    home.packages = [ command ];
  };
}
