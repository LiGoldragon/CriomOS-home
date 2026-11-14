{ pkgs, inputs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  user = {
    name = "li";
    size = "Min";
    capabilities = [ ];
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs user;
        horizon.node.behavesAs.edge = false;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-remote-control.nix
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
  expectedRetainedStablePackage = pkgs.callPackage "${inputs.deployed-codex-source}/owned-agents/codex" {
    manifestFile = "${inputs.deployed-codex-source}/owned-agents/codex/stable-hashes.json";
  };
  expectedPathPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  pathPackage = builtins.head (
    builtins.filter (package: lib.getName package == "codex") configuration.home.packages
  );
  stableClient = configuration.criomosHome.herdr.stableCodexClientPackage;
  nextRaw = configuration.criomosHome.codexNextCandidate.package;
  nextClient = configuration.criomosHome.codexNextCandidate.clientPackage;
  nextRemoteClient = configuration.criomosHome.codexNextCandidate.remoteClientPackage;
  configToml = builtins.readFile configuration.xdg.configFile."herdr/config.toml".source;
in
assert
  builtins.match ".*codex_executables.*codex-stable-flow-client.*codex-next-flow-client.*" configToml
  != null;
assert expectedRetainedStablePackage.version == "0.163.0";
assert expectedPathPackage.version == "0.169.0";
assert pathPackage == expectedPathPackage;
assert pathPackage != expectedRetainedStablePackage;
pkgs.runCommand "herdr-agent-executable-contract" { } ''
  set -eu
  stable=${stableClient}/bin/codex-stable-flow-client
  next=${nextClient}/bin/codex-next-flow-client
  remote=${nextRemoteClient}/bin/codex-next

  grep -F 'export CODEX_HOME=' "$stable"
  grep -F 'exec ${expectedRetainedStablePackage}/bin/codex "$@"' "$stable"
  ! grep -F 'exec ${expectedPathPackage}/bin/codex "$@"' "$stable"
  ! grep -F -- '--remote' "$stable"
  grep -F 'export CODEX_HOME=' "$next"
  grep -F 'exec ${nextRaw}/bin/codex "$@"' "$next"
  ! grep -F -- '--remote' "$next"
  grep -F -- '--remote' "$remote"

  ${herdrPackage}/bin/herdr --help | grep -F 'agent <subcommand>'
  mkdir -p "$out"
  cp ${configuration.xdg.configFile."herdr/config.toml".source} "$out/config.toml"
''
