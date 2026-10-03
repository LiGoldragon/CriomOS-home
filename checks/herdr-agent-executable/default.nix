{ pkgs, inputs, ... }:
let
  user = { name = "li"; size = "Min"; };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs user; };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/codex-next-candidate.nix
        ../../modules/home/profiles/min/herdr.nix
        {
          home.username = user.name;
          home.homeDirectory = "/home/li";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  herdrPackage = configuration.criomosHome.herdr.package;
  stableClient = configuration.criomosHome.herdr.stableCodexClientPackage;
  nextRaw = configuration.criomosHome.codexNextCandidate.package;
  nextClient = configuration.criomosHome.codexNextCandidate.clientPackage;
  nextRemoteClient = configuration.criomosHome.codexNextCandidate.remoteClientPackage;
  configToml = builtins.readFile configuration.xdg.configFile."herdr/config.toml".source;
in
assert builtins.match ".*codex_executables.*codex-stable-flow-client.*codex-next-flow-client.*" configToml != null;
pkgs.runCommand "herdr-agent-executable-contract" { } ''
  set -eu
  stable=${stableClient}/bin/codex-stable-flow-client
  next=${nextClient}/bin/codex-next-flow-client
  remote=${nextRemoteClient}/bin/codex-next

  grep -F 'export CODEX_HOME=' "$stable"
  grep -F 'exec ${configuration.criomos.corePackages.codex}/bin/codex "$@"' "$stable"
  ! grep -F -- '--remote' "$stable"
  grep -F 'export CODEX_HOME=' "$next"
  grep -F 'exec ${nextRaw}/bin/codex "$@"' "$next"
  ! grep -F -- '--remote' "$next"
  grep -F -- '--remote' "$remote"

  ${herdrPackage}/bin/herdr --help | grep -F 'agent <subcommand>'
  mkdir -p "$out"
  cp ${configuration.xdg.configFile."herdr/config.toml".source} "$out/config.toml"
''
