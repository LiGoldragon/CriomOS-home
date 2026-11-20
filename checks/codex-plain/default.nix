{ pkgs }:
let
  inherit (pkgs) lib;
  package = pkgs.callPackage ../../owned-agents/codex-plain {};
  evaluate = enabled: (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ../../modules/home/profiles/min/codex-plain.nix
      ({ lib, ... }: {
        options.home.homeDirectory = lib.mkOption { type = lib.types.str; default = "/home/fixture"; };
        options.home.packages = lib.mkOption { type = lib.types.listOf lib.types.package; default = []; };
        options.systemd.user.services = lib.mkOption { type = lib.types.attrs; default = {}; };
        config.criomosHome.codexPlain.enable = enabled;
      })
    ];
  }).config;
  disabled = evaluate false;
  enabled = evaluate true;
  cfg = enabled.criomosHome.codexPlain;
  unit = enabled.systemd.user.services.${cfg.unit};
in
assert disabled.systemd.user.services == {};
assert disabled.home.packages == [];
assert enabled.home.packages == [ cfg.clientPackage ];
assert !cfg.autoStart;
assert cfg.authSource == null;
assert unit.Install.WantedBy == [];
assert unit.Service.Restart == "no";
assert unit.Unit."X-SwitchMethod" == "keep-old";
assert lib.hasInfix ".codex-plain-" cfg.homeDirectory;
assert unit.Service.Environment == [ "CODEX_HOME=${cfg.homeDirectory}" ];
pkgs.runCommand "codex-plain-contract" {} ''
  ${package}/bin/codex --version | grep -Fx 'codex-cli 0.171.0'
  if env -u CODEX_HOME ${package.flowClient}/bin/codex-plain-flow-client --version; then
    echo 'private-home precondition was not enforced' >&2
    exit 1
  fi
  CODEX_HOME="$TMPDIR/private-home" ${package.flowClient}/bin/codex-plain-flow-client --version | grep -Fx 'codex-cli 0.171.0'
  mkdir "$out"
  ln -s ${package} "$out/server"
  ln -s ${package.flowClient} "$out/client"
''
