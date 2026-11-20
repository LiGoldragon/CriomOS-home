{ pkgs, inputs, ... }:
let
  mk =
    node: synchronizations:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        horizon = {
          node.name = node;
          exNodes.replica.criomeDomainName = "replica.cluster.example";
        };
        user = {
          name = "example";
          inherit synchronizations;
        };
      };
      modules = [
        ../../modules/home/unison.nix
        {
          home.username = "example";
          home.homeDirectory = "/home/example";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  synchronization = {
    master = "master";
    replica = "replica";
    tree = "code";
  };
  master = mk "master" [ synchronization ];
  replica = mk "replica" [ synchronization ];
  other = mk "other" [ synchronization ];
  service = builtins.head (builtins.attrValues master.systemd.user.services);
  command = builtins.head service.Service.ExecStart;
  profileName = builtins.unsafeDiscardStringContext (
    builtins.elemAt (pkgs.lib.splitString " " command) 1
  );
  profile = master.home.file.".unison/${profileName}.prf".source;
in
assert builtins.length (builtins.attrNames master.systemd.user.services) == 1;
assert replica.systemd.user.services == { };
assert other.systemd.user.services == { };
assert builtins.elem master.criomos.unison.package replica.home.packages;
assert service.Service.Restart == "on-failure";
assert builtins.elem (toString profile) service.Unit.X-Restart-Triggers;
assert service.Unit.StartLimitBurst == 3;
assert service.Unit.StartLimitIntervalSec == "5min";
assert builtins.elem "SSH_AUTH_SOCK=%t/gnupg/S.gpg-agent.ssh" service.Service.Environment;
pkgs.runCommand "unison-user-module-contract"
  {
    nativeBuildInputs = [
      pkgs.python3
      master.criomos.unison.package
    ];
  }
  ''
    set -eu
    grep -Fx 'root = /home/example/code' ${profile}
    grep -Fx 'root = ssh://example@replica.cluster.example//home/example/code' ${profile}
    grep -Fx 'repeat = watch' ${profile}
    grep -Fx 'batch = true' ${profile}
    grep -Fx 'prefer = /home/example/code' ${profile}
    grep -Fx 'times = false' ${profile}
    grep -Fx 'sshargs = -oBatchMode=yes' ${profile}
    grep -Fx 'ignore = Name target' ${profile}
    grep -Fx 'ignore = Name result' ${profile}
    grep -Fx 'ignore = Name .direnv' ${profile}
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python3 ${./replicas.py} ${master.criomos.unison.package}/bin/unison
    touch "$out"
  ''
