{ pkgs, inputs, ... }:
let
  mk =
    node: synchronizations: homeDirectory:
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
          home.homeDirectory = homeDirectory;
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  synchronization = {
    master = "master";
    replica = "replica";
    tree = "code";
  };
  master = mk "master" [ synchronization ] "/home/example";
  replica = mk "replica" [ synchronization ] "/home/example";
  other = mk "other" [ synchronization ] "/home/example";
  invalidHomes = map (path: mk "master" [ synchronization ] path) [
    "/home/example "
    "/home/example\t"
    "/home/ex\rample"
    "/home/ex\nample"
  ];
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
assert builtins.all (
  configuration: !(builtins.tryEval configuration.home.homeDirectory).success
) invalidHomes;
assert service.Service.Restart == "on-failure";
assert builtins.elem (toString profile) service.Unit.X-Restart-Triggers;
assert service.Unit.StartLimitBurst == 3;
assert service.Unit.StartLimitIntervalSec == 300;
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
    grep -F -- '-oBatchMode=yes' ${profile}
    grep -F -- '-oIdentityAgent=SSH_AUTH_SOCK' ${profile}
    grep -F -- '-oStrictHostKeyChecking=yes' ${profile}
    grep -Fx 'ignore = Name target' ${profile}
    grep -Fx 'ignore = Name result' ${profile}
    grep -Fx 'ignore = Name .direnv' ${profile}
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python3 ${./replicas.py} ${master.criomos.unison.package}/bin/unison ${profile} ${master.criomos.unison.sshPackage}/bin/ssh
    touch "$out"
  ''
